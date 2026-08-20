import Foundation
import CoreLocation
import SwiftData
import Observation

/// Owns the singleton `CLLocationManager` and runs the trip lifecycle.
///
/// Tracking strategy (see plan for full rationale):
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

    // MARK: - Dependencies

    /// Set by `App` so the manager can fire the audio alarm.
    weak var alarmManager: AlarmManager?

    // MARK: - Private

    private let manager = CLLocationManager()
    private var armedStop: BusStop?
    private var armedStopID: PersistentIdentifier?
    private var isWithinRadius = false
    /// Extra margin beyond `radius` before we consider the user "out" again.
    /// Prevents the alarm from oscillating when the boundary is fuzzy.
    private let hysteresisMargin: Double = 500
    private var didConfigureForBackground = false

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

    // MARK: - Trip lifecycle

    /// Begin a trip to `stop`. Disarms any existing trip first.
    /// Requires at least `When In Use` authorization.
    func arm(stop: BusStop) {
        disarmMonitoring()

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
            identifier: "stop.\(stop.persistentModelID.hashValue)"
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

    /// Stop the active trip and tear down all monitoring.
    func disarm() {
        disarmMonitoring()
        tripState = .idle
        isMonitoring = false
    }

    /// Acknowledge the active alarm and stop everything.
    func dismissAlarm() {
        alarmManager?.stop()
        disarmMonitoring()
        tripState = .idle
        isMonitoring = false
    }

    /// Useful for previews / tests; bypasses CLLocationManager.
    func _testEvaluate(location: CLLocation) {
        evaluate(location: location)
    }

    // MARK: - Private helpers

    private func disarmMonitoring() {
        for region in manager.monitoredRegions {
            manager.stopMonitoring(for: region)
        }
        manager.stopUpdatingLocation()
        manager.stopMonitoringSignificantLocationChanges()
        manager.allowsBackgroundLocationUpdates = false
        didConfigureForBackground = false
        armedStop = nil
        armedStopID = nil
        isWithinRadius = false
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
            guard let stop = self.armedStop,
                  let stopID = self.armedStopID,
                  circular.center.latitude == stop.latitude,
                  circular.center.longitude == stop.longitude
            else { return }
            // Confirm against last continuous fix before firing.
            if let loc = self.currentLocation {
                self.evaluate(location: loc)
            } else {
                self.isWithinRadius = true
                self.triggerAlarm(
                    stopID: stopID,
                    name: stop.name,
                    distance: circular.radius
                )
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            // If we upgrade to Always mid-trip, enable background updates.
            if self.isMonitoring {
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
}