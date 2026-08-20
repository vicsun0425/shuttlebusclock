import XCTest
import CoreLocation
@testable import ShuttleBusClock

/// Tests the trip state machine that `ContentView` routes on.
///
/// `ContentView` switches purely on `LocationManager.tripState`
/// (.idle → StopListView, .armed → ArmedTripView, .alerting → ActiveAlarmView),
/// so asserting on `tripState` here is equivalent to asserting which screen the
/// user is looking at. `alarmManager` is deliberately left nil so triggering an
/// alarm doesn't try to start real audio.
@MainActor
final class TripStateMachineTests: XCTestCase {

    private var manager: LocationManager!
    private let destination = CLLocation(latitude: 39.9042, longitude: 116.4074)
    private lazy var stop: BusStop = BusStop(
        name: "公司",
        latitude: destination.coordinate.latitude,
        longitude: destination.coordinate.longitude,
        radius: 3000
    )
    private lazy var otherStop: BusStop = BusStop(
        name: "家",
        latitude: 31.2304,
        longitude: 121.4737,
        radius: 3000
    )

    override func setUp() async throws {
        try await super.setUp()
        manager = LocationManager()
    }

    override func tearDown() async throws {
        manager.disarm()
        manager = nil
        try await super.tearDown()
    }

    // MARK: - Arming

    func testStartsIdle() {
        XCTAssertEqual(manager.tripState, .idle)
        XCTAssertFalse(manager.isMonitoring)
    }

    func testArmMovesToArmedState() {
        manager.arm(stop: stop)
        XCTAssertEqual(manager.tripState, .armed(stopID: stop.persistentModelID))
        XCTAssertTrue(manager.isMonitoring)
    }

    // MARK: - The 取消行程 button

    func testDisarmReturnsToIdle() {
        manager.arm(stop: stop)
        XCTAssertEqual(manager.tripState, .armed(stopID: stop.persistentModelID))

        manager.disarm()

        XCTAssertEqual(manager.tripState, .idle, "取消行程后必须回到列表页")
        XCTAssertFalse(manager.isMonitoring, "取消行程后不应继续监测")
    }

    func testDisarmStopsEvaluatingLocationUpdates() {
        manager.arm(stop: stop)
        manager.disarm()

        // A location update queued before the disarm must not resurrect the trip.
        manager._testEvaluate(location: destination)

        XCTAssertEqual(manager.tripState, .idle,
                       "取消后收到的定位回调不应把行程拉回来")
    }

    func testDisarmIsIdempotent() {
        manager.arm(stop: stop)
        manager.disarm()
        manager.disarm()
        XCTAssertEqual(manager.tripState, .idle)
    }

    func testDisarmWithoutArmingIsHarmless() {
        manager.disarm()
        XCTAssertEqual(manager.tripState, .idle)
    }

    // MARK: - Alarm acknowledgement

    func testDismissAlarmReturnsToIdle() {
        manager.arm(stop: stop)
        manager._testEvaluate(location: destination)
        XCTAssertEqual(manager.tripState, .alerting(stopID: stop.persistentModelID))

        manager.dismissAlarm()

        XCTAssertEqual(manager.tripState, .idle, "点『我醒了』后必须回到列表页")
        XCTAssertFalse(manager.isMonitoring)
    }

    func testCancelWhileAlarmingAlsoReturnsToIdle() {
        // The alarm screen only offers 我醒了, but disarm must be safe from the
        // alerting state too — nothing should be able to strand the user there.
        manager.arm(stop: stop)
        manager._testEvaluate(location: destination)
        manager.disarm()
        XCTAssertEqual(manager.tripState, .idle)
    }

    // MARK: - Switching targets

    func testArmingAnotherStopReplacesTheTrip() {
        manager.arm(stop: stop)
        manager.arm(stop: otherStop)

        XCTAssertEqual(manager.tripState, .armed(stopID: otherStop.persistentModelID))

        // Distance must now be measured against the new stop, not the old one.
        manager._testEvaluate(location: destination)
        XCTAssertNotEqual(manager.tripState, .alerting(stopID: stop.persistentModelID),
                          "站在旧站点上不应触发新行程的闹钟")
    }

    func testReArmingSameStopClearsPriorTriggerState() {
        manager.arm(stop: stop)
        manager._testEvaluate(location: destination)
        XCTAssertEqual(manager.tripState, .alerting(stopID: stop.persistentModelID))

        manager.dismissAlarm()
        manager.arm(stop: stop)
        XCTAssertEqual(manager.tripState, .armed(stopID: stop.persistentModelID))

        // Hysteresis state must have been reset, so it can fire again.
        manager._testEvaluate(location: destination)
        XCTAssertEqual(manager.tripState, .alerting(stopID: stop.persistentModelID),
                       "重新启动行程后应能再次触发")
    }

    // MARK: - Schedule interaction

    func testManualArmIgnoresMasterSwitchAndSchedule() {
        // Manual arming is an override: tapping a stop must always start a trip
        // regardless of the schedule settings.
        let saved = ScheduleSettings.masterEnabled
        defer { ScheduleSettings.masterEnabled = saved }
        ScheduleSettings.masterEnabled = false

        stop.isScheduleEnabled = true
        stop.effectiveWeekdayMask = 0          // no day selected
        stop.startMinute = 0
        stop.endMinute = 0                     // empty window

        manager.arm(stop: stop)
        XCTAssertEqual(manager.tripState, .armed(stopID: stop.persistentModelID))

        manager._testEvaluate(location: destination)
        XCTAssertEqual(manager.tripState, .alerting(stopID: stop.persistentModelID),
                       "手动行程不受总开关和时段限制")
    }
}
