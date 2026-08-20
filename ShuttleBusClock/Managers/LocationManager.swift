import Foundation
import CoreLocation
import SwiftData
import Observation

/// Owns the singleton `CLLocationManager` and runs the trip lifecycle.
///
/// Two independent monitoring modes share one `CLLocationManager`:
///
///   * **Manual trip** (`armed.*` regions) — the user taps a stop, we stream
///     continuous location for the live readout and fire on threshold. Torn
///     down when the trip ends. Unaffected by any schedule setting.
///   * **Scheduled monitoring** (`sched.*` regions) — geofences registered for
///     every schedule-enabled stop and left registered indefinitely. iOS
///     persists these across app termination and reboot, so the alarm still
///     works months later without the user opening the app. On entry we ask
///     `ScheduleEvaluator` whether the current weekday/time allows ringing.
///
/// The prefixes matter: the two modes must never tear down each other's
/// regions, which is why nothing here calls `stopMonitoring` over the whole set.
///
/// Tracking strategy for a manual trip:
///   * Region monitoring (`CLCircularRegion` at the stop's radius) is the
///     primary wake-up event — hardware-backed, survives suspension.
///   * Continuous location updates provide the "X km away" readout and act
///     as a resilience path if region monitoring fails to fire.
///   * Significant location changes give us a "the device moved" wake after
///     long suspensions (e.g. signal lost in a tunnel).
///
/// All threshold decisions use a 500 m hysteresis to prevent oscillation
/// across the boundary.
@Observable
@MainActor
final class LocationManager: NSObject {
    // MARK: - Public state observed by SwiftUI

    /// Current CoreLocation authorization status.
    var authorizationStatus: CLAuthorizationStatus

    /// Most recent user location fix.
    var currentLocation: CLLocation?

    /// Live distance (meters) to the currently armed stop's destination, or nil.
    var distanceToTarget: Double?

    /// Whether continuous updates are currently streaming (armed trip).
    var isMonitoring: Bool = false

    /// Trip state machine, sourced from `TripState`.
    var tripState: TripState = .idle

    /// Last CoreLocation error message, for the UI.
    var lastError: String?

    // MARK: - Scheduled monitoring state

    enum ScheduleStatus: Equatable {
        case off
        case noEligibleStops
        case active(registered: Int, enabled: Int)
        case overLimit(registered: Int, enabled: Int)
        case failed(String)
    }

    /// Reflects what CoreLocation *actually* accepted, not what we asked for.
    var scheduleStatus: ScheduleStatus = .off

    struct ScheduleLogEntry: Identifiable, Equatable {
        let id = UUID()
        let stopName: String
        let decision: ScheduleEvaluator.Decision
        let at: Date
    }

    /// Recent geofence entries and what the schedule decided, newest first.
    /// This is the user-facing evidence that the switches are doing something.
    var scheduleLog: [ScheduleLogEntry] = []

    /// iOS allows 20 monitored regions per app. Leave headroom for the manual
    /// trip and for CoreLocation's own bookkeeping.
    static let maxScheduleRegions = 15

    // MARK: - Dependencies

    /// Set by `App` so the manager can fire the audio alarm.
    weak var alarmManager: AlarmManager?

    /// Set by `App`. Needed because a geofence can relaunch the app straight
    /// into the background, where no SwiftUI view has run to hand us stops.
    var modelContainer: ModelContainer?

    // MARK: - Private

    private let manager = CLLocationManager()
    private var armedStop: BusStop?
    private var armedStopID: PersistentIdentifier?
    private var isWithinRadius = false
    /// Extra margin beyond `radius` before we consider the user "out" again.
    /// Prevents the alarm from oscillating when the boundary is fuzzy.
    private let hysteresisMargin: Double = 500
    private var didConfigureForBackground = false

    private static let armedPrefix = "armed."
    private static let schedPrefix = "sched."

    /// Region identifiers we've asked CoreLocation to monitor but that haven't
    /// been confirmed yet. Registration succeeds or fails asynchronously.
    private var pendingScheduleRegionIDs: Set<String> = []
    private var confirmedScheduleRegionIDs: Set<String> = []

    override init() {
        self.authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 500
        manager.activityType = .automotiveNavigation
        // Default false; we only flip it on once we have Always auth.
        manager.allowsBackgroundLocationUpdates = false
        // CRITICAL: otherwise iOS pauses updates when it thinks the user
        // is stationary, which on a stopped shuttle looks identical.
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = true
    }

    // MARK: - Permissions

    /// Step 1 of the two-step permission flow. Call this when the user first
    /// creates a stop or taps "arm trip".
    func requestWhenInUseAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    /// Step 2. Only meaningful after `requestWhenInUseAuthorization()` resolves
    /// to `.authorizedWhenInUse`. Will silently no-op otherwise.
    func requestAlwaysAuthorization() {
        guard authorizationStatus == .authorizedWhenInUse else { return }
        manager.requestAlwaysAuthorization()
    }

    // MARK: - Trip lifecycle (manual)

    /// Begin a trip to `stop`. Disarms any existing trip first.
    /// Requires at least `When In Use` authorization.
    ///
    /// Manual arming is an override: it ignores the master switch and the
    /// stop's schedule entirely. Tapping a stop always starts a trip.
    func arm(stop: BusStop) {
        disarmForegroundTrip()

        armedStop = stop
        armedStopID = stop.persistentModelID
        isWithinRadius = false
        distanceToTarget = nil
        lastError = nil

        // Continuous updates for the live distance readout.
        manager.startUpdatingLocation()

        // Significant-change as the post-suspension wake-up fallback.
        manager.startMonitoringSignificantLocationChanges()

        // Region monitoring — primary trigger.
        let region = CLCircularRegion(
            center: stop.coordinate,
            radius: stop.radius,
            identifier: Self.armedPrefix + stop.stableID
        )
        region.notifyOnEntry = true
        region.notifyOnExit = false  // hysteresis owns re-arming
        manager.startMonitoring(for: region)

        // Background updates only when we have Always auth — otherwise
        // setting this flag can cause the app to crash on iOS.
        configureBackgroundFlagForCurrentAuth()

        tripState = .armed(stopID: stop.persistentModelID)
        isMonitoring = true
    }

    /// Stop the active trip and tear down manual monitoring.
    func disarm() {
        disarmForegroundTrip()
        tripState = .idle
        isMonitoring = false
    }

    /// Acknowledge the active alarm and stop everything *for this trip*.
    ///
    /// Scheduled geofences deliberately survive this. Tearing them down here is
    /// what made the old build a one-shot: after the alarm was acknowledged the
    /// app forgot everything and the next morning required a manual re-arm.
    func dismissAlarm() {
        alarmManager?.stop()
        disarmForegroundTrip()
        tripState = .idle
        isMonitoring = false
    }

    /// Useful for previews / tests; bypasses CLLocationManager.
    func _testEvaluate(location: CLLocation) {
        evaluate(location: location)
    }

    // MARK: - Scheduled monitoring

    /// Bring the set of registered `sched.*` regions in line with `stops`.
    ///
    /// Incremental: only adds what's missing and removes what's no longer
    /// eligible, so an unrelated save doesn't churn every geofence.
    func reconcileScheduleRegions(with stops: [BusStop]) {
        let masterOn = ScheduleSettings.masterEnabled
        let eligible = masterOn ? stops.filter(\.isScheduleEnabled) : []
        let admitted = Array(eligible.prefix(Self.maxScheduleRegions))
        let desiredIDs = Set(admitted.map { Self.schedPrefix + $0.stableID })

        for region in manager.monitoredRegions
        where region.identifier.hasPrefix(Self.schedPrefix) && !desiredIDs.contains(region.identifier) {
            manager.stopMonitoring(for: region)
            confirmedScheduleRegionIDs.remove(region.identifier)
            pendingScheduleRegionIDs.remove(region.identifier)
        }

        let alreadyMonitored = Set(manager.monitoredRegions.map(\.identifier))
        for stop in admitted {
            let identifier = Self.schedPrefix + stop.stableID
            guard !alreadyMonitored.contains(identifier) else {
                confirmedScheduleRegionIDs.insert(identifier)
                continue
            }
            let region = CLCircularRegion(
                center: stop.coordinate,
                radius: stop.radius,
                identifier: identifier
            )
            region.notifyOnEntry = true
            // Exit matters here: iOS won't re-fire an entry until the device
            // has left the region, so we need the exit to know we're outside
            // again for tomorrow's commute.
            region.notifyOnExit = true
            pendingScheduleRegionIDs.insert(identifier)
            manager.startMonitoring(for: region)
        }

        if masterOn, !eligible.isEmpty {
            configureBackgroundFlagForCurrentAuth()
        }
        updateScheduleStatus(enabledCount: eligible.count, masterOn: masterOn)
    }

    /// Re-runs the schedule decision for a stop right now. Drives the live
    /// "生效中 / 未生效(原因)" readout in the schedule editor.
    func currentDecision(for stop: BusStop, at date: Date = Date()) -> ScheduleEvaluator.Decision {
        ScheduleEvaluator.current.decide(
            stop: stop,
            masterEnabled: ScheduleSettings.masterEnabled,
            at: date
        )
    }

    private func updateScheduleStatus(enabledCount: Int, masterOn: Bool) {
        guard masterOn else { scheduleStatus = .off; return }
        guard enabledCount > 0 else { scheduleStatus = .noEligibleStops; return }
        let registered = confirmedScheduleRegionIDs.count
        scheduleStatus = enabledCount > Self.maxScheduleRegions
            ? .overLimit(registered: registered, enabled: enabledCount)
            : .active(registered: registered, enabled: enabledCount)
    }

    /// Resolve a `sched.*` identifier back to its stop.
    ///
    /// Falls back to a fresh fetch because a geofence can relaunch the app
    /// directly into the background, where no view has handed us anything.
    private func scheduledStop(forRegionIdentifier identifier: String) -> BusStop? {
        let stableID = String(identifier.dropFirst(Self.schedPrefix.count))
        guard let container = modelContainer else { return nil }
        let context = ModelContext(container)
        let all = (try? context.fetch(FetchDescriptor<BusStop>())) ?? []
        return all.first { $0.stopUUID == stableID }
    }

    private func handleScheduledEntry(_ region: CLCircularRegion) {
        guard let stop = scheduledStop(forRegionIdentifier: region.identifier) else {
            lastError = "无法匹配定时站点(\(region.identifier))"
            return
        }

        let decision = currentDecision(for: stop)
        scheduleLog.insert(
            ScheduleLogEntry(stopName: stop.name, decision: decision, at: Date()),
            at: 0
        )
        if scheduleLog.count > 20 { scheduleLog.removeLast(scheduleLog.count - 20) }

        guard decision.isFiring else { return }

        let distance = currentLocation?.distance(from: stop.location) ?? region.radius
        armedStop = stop
        armedStopID = stop.persistentModelID
        isWithinRadius = true
        distanceToTarget = distance
        triggerAlarm(stopID: stop.persistentModelID, name: stop.name, distance: distance)
    }

    // MARK: - Private helpers

    /// Stops only the manual-trip monitoring. Scheduled geofences are left
    /// alone — see `dismissAlarm`.
    private func disarmForegroundTrip() {
        for region in manager.monitoredRegions
        where region.identifier.hasPrefix(Self.armedPrefix) {
            manager.stopMonitoring(for: region)
        }
        manager.stopUpdatingLocation()
        manager.stopMonitoringSignificantLocationChanges()
        armedStop = nil
        armedStopID = nil
        isWithinRadius = false

        // Only drop the background flag when nothing else needs it.
        if confirmedScheduleRegionIDs.isEmpty && pendingScheduleRegionIDs.isEmpty {
            manager.allowsBackgroundLocationUpdates = false
            didConfigureForBackground = false
        }
    }

    private func configureBackgroundFlagForCurrentAuth() {
        let needsBackground = (authorizationStatus == .authorizedAlways)
        if needsBackground && !didConfigureForBackground {
            manager.allowsBackgroundLocationUpdates = true
            didConfigureForBackground = true
        } else if !needsBackground && didConfigureForBackground {
            manager.allowsBackgroundLocationUpdates = false
            didConfigureForBackground = false
        }
    }

    private func evaluate(location: CLLocation) {
        currentLocation = location
        guard let stop = armedStop, let stopID = armedStopID else { return }
        let distance = location.distance(from: stop.location)
        distanceToTarget = distance

        // Hysteresis:
        //   enter when  distance <= radius
        //   leave when  distance >  radius + hysteresisMargin
        if !isWithinRadius && distance <= stop.radius {
            isWithinRadius = true
            triggerAlarm(stopID: stopID, name: stop.name, distance: distance)
        } else if isWithinRadius && distance > stop.radius + hysteresisMargin {
            isWithinRadius = false
        }
    }

    private func triggerAlarm(stopID: PersistentIdentifier, name: String, distance: Double) {
        tripState = .alerting(stopID: stopID)
        alarmManager?.start(stopName: name, distance: distance)
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationManager: CLLocationManagerDelegate {

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let last = locations.last else { return }
        Task { @MainActor in
            self.evaluate(location: last)
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didEnterRegion region: CLRegion
    ) {
        guard let circular = region as? CLCircularRegion else { return }
        Task { @MainActor in
            if circular.identifier.hasPrefix(Self.schedPrefix) {
                self.handleScheduledEntry(circular)
            } else {
                self.handleArmedEntry(circular)
            }
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didStartMonitoringFor region: CLRegion
    ) {
        let identifier = region.identifier
        Task { @MainActor in
            guard identifier.hasPrefix(Self.schedPrefix) else { return }
            self.pendingScheduleRegionIDs.remove(identifier)
            self.confirmedScheduleRegionIDs.insert(identifier)
            self.refreshScheduleStatusFromCurrentState()
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        monitoringDidFailFor region: CLRegion?,
        withError error: Error
    ) {
        let identifier = region?.identifier
        let message = error.localizedDescription
        Task { @MainActor in
            if let identifier, identifier.hasPrefix(Self.schedPrefix) {
                self.pendingScheduleRegionIDs.remove(identifier)
                self.confirmedScheduleRegionIDs.remove(identifier)
            }
            // Surface it — a geofence that silently failed to register looks
            // exactly like one that works until the morning it doesn't.
            self.scheduleStatus = .failed("围栏注册失败:\(message)")
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            // If we upgrade to Always mid-trip, enable background updates.
            if self.isMonitoring || !self.confirmedScheduleRegionIDs.isEmpty {
                self.configureBackgroundFlagForCurrentAuth()
            }
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        let message = error.localizedDescription
        Task { @MainActor in
            self.lastError = message
        }
    }

    // MARK: - Entry handling

    private func handleArmedEntry(_ circular: CLCircularRegion) {
        guard let stop = armedStop,
              let stopID = armedStopID,
              circular.center.latitude == stop.latitude,
              circular.center.longitude == stop.longitude
        else { return }
        // Confirm against last continuous fix before firing.
        if let loc = currentLocation {
            evaluate(location: loc)
        } else {
            isWithinRadius = true
            triggerAlarm(stopID: stopID, name: stop.name, distance: circular.radius)
        }
    }

    private func refreshScheduleStatusFromCurrentState() {
        let enabled = max(confirmedScheduleRegionIDs.count + pendingScheduleRegionIDs.count, 0)
        updateScheduleStatus(enabledCount: enabled, masterOn: ScheduleSettings.masterEnabled)
    }
}
