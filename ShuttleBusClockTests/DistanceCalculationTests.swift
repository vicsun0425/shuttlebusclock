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

    func testDistanceUpdatesOnEachEvaluation() {
        let farLocation = offsetLocation(from: destination, meters: 10_000)
        manager._testEvaluate(location: farLocation)
        XCTAssertEqual(manager.distanceToTarget, 10_000, accuracy: 5)
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

    /// Returns a CLLocation `meters` meters away from `origin` along an
    /// arbitrary bearing. Uses a simple lat/lon offset approximation good
    /// enough for test distances (<100 km).
    private func offsetLocation(from origin: CLLocation, meters: Double) -> CLLocation {
        // 1 degree latitude ≈ 111,320 meters.
        let deltaLat = meters / 111_320
        let newLocation = CLLocation(
            latitude: origin.coordinate.latitude + deltaLat,
            longitude: origin.coordinate.longitude
        )
        return newLocation
    }
}