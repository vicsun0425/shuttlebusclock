import XCTest
import CoreLocation
@testable import ShuttleBusClock

/// Unit tests for the LocationManager distance / hysteresis logic.
///
/// We drive the manager through the private `_testEvaluate(location:)` seam
/// rather than mocking CLLocationManager directly — this exercises the real
/// decision code, including the `isWithinRadius` state machine.
@MainActor
final class DistanceCalculationTests: XCTestCase {
    private var manager: LocationManager!
    private let destination = CLLocation(latitude: 39.9042, longitude: 116.4074)
    private lazy var stop: BusStop = BusStop(
        name: "Test Stop",
        latitude: destination.coordinate.latitude,
        longitude: destination.coordinate.longitude,
        radius: 3000
    )

    override func setUp() async throws {
        try await super.setUp()
        manager = LocationManager()
        // Bypass CLLocationManager entirely by arming through the test seam.
        manager.arm(stop: stop)
    }

    override func tearDown() async throws {
        manager.disarm()
        manager = nil
        try await super.tearDown()
    }

    // MARK: - Distance updates

    func testDistanceUpdatesOnEachEvaluation() throws {
        let farLocation = offsetLocation(from: destination, meters: 10_000)
        manager._testEvaluate(location: farLocation)
        let distance = try XCTUnwrap(manager.distanceToTarget)
        XCTAssertEqual(distance, 10_000, accuracy: 5)
        XCTAssertNotEqual(manager.tripState, .alerting(stopID: stop.persistentModelID))
    }

    // MARK: - Trigger boundary

    func testAlarmTriggersAtOrInsideRadius() {
        let justOutside = offsetLocation(from: destination, meters: 3_001)
        manager._testEvaluate(location: justOutside)
        XCTAssertNotEqual(manager.tripState, .alerting(stopID: stop.persistentModelID),
                          "Should not fire just outside the radius")

        let justInside = offsetLocation(from: destination, meters: 2_999)
        manager._testEvaluate(location: justInside)
        XCTAssertEqual(manager.tripState, .alerting(stopID: stop.persistentModelID),
                       "Should fire just inside the radius")
    }

    func testAlarmFiresAtExactRadius() {
        let atRadius = offsetLocation(from: destination, meters: 3_000)
        manager._testEvaluate(location: atRadius)
        XCTAssertEqual(manager.tripState, .alerting(stopID: stop.persistentModelID),
                       "Should fire when distance equals the configured radius")
    }

    // MARK: - Hysteresis

    func testHysteresisPreventsImmediateClearAfterTrigger() {
        // Fire the alarm.
        let inside = offsetLocation(from: destination, meters: 1000)
        manager._testEvaluate(location: inside)
        XCTAssertEqual(manager.tripState, .alerting(stopID: stop.persistentModelID))

        // Move to radius + 100m (within the 500m hysteresis margin).
        let slightlyOutside = offsetLocation(from: destination, meters: 3_100)
        manager._testEvaluate(location: slightlyOutside)
        XCTAssertEqual(manager.tripState, .alerting(stopID: stop.persistentModelID),
                       "Should stay alerting while within radius + hysteresis margin")

        // Move well past radius + margin.
        let farOutside = offsetLocation(from: destination, meters: 5_000)
        manager._testEvaluate(location: farOutside)
        XCTAssertEqual(manager.tripState, .alerting(stopID: stop.persistentModelID),
                       "Should remain alerting until user dismisses — hysteresis only controls re-arm")
    }

    // MARK: - Manual dismiss

    func testDismissAlarmStopsTrip() {
        let inside = offsetLocation(from: destination, meters: 500)
        manager._testEvaluate(location: inside)
        XCTAssertEqual(manager.tripState, .alerting(stopID: stop.persistentModelID))

        manager.dismissAlarm()
        XCTAssertEqual(manager.tripState, .idle)
    }

    // MARK: - Helpers

    /// Returns a CLLocation `meters` due north of `origin`, accurate to well
    /// under a millimetre *as measured by the code under test*.
    ///
    /// Three traps here, all of which silently broke the boundary assertions:
    ///  1. CLLocation measures on the WGS-84 ellipsoid, where a degree of
    ///     latitude is ~111,032 m at Beijing — not the 111,320 m average a
    ///     hard-coded constant assumes. That 0.26 % error put a "3,001 m"
    ///     point *inside* a 3,000 m radius.
    ///  2. One division leaves residue, so we refine against real measurements.
    ///  3. `distance(from:)` is **not symmetric** — measured here, the two
    ///     directions between the same pair of points differ by ~4.4 mm at
    ///     3 km. `LocationManager.evaluate` computes
    ///     `currentLocation.distance(from: stop.location)`, so we must refine
    ///     in that same orientation or we land on the wrong side of the line.
    ///
    /// The result is biased a hair inward so it sits at-or-just-inside the
    /// requested distance, keeping assertions on the inclusive
    /// `distance <= radius` boundary deterministic.
    private func offsetLocation(from origin: CLLocation, meters: Double) -> CLLocation {
        func candidate(_ delta: Double) -> CLLocation {
            CLLocation(
                latitude: origin.coordinate.latitude + delta,
                longitude: origin.coordinate.longitude
            )
        }
        // Same orientation as LocationManager.evaluate.
        func measured(_ delta: Double) -> Double {
            candidate(delta).distance(from: origin)
        }

        let probeDelta = 0.01  // ~1.1 km: local enough that curvature doesn't skew it
        var delta = meters / (measured(probeDelta) / probeDelta)

        for _ in 0..<4 {
            let actual = measured(delta)
            guard actual > 0 else { break }
            delta *= meters / actual
        }
        // Nudge inward by ~3 µm at 3 km — far below any distance this app
        // cares about, but enough to settle the last floating-point bit.
        while measured(delta) > meters {
            delta *= 1 - 1e-9
        }

        return candidate(delta)
    }
}