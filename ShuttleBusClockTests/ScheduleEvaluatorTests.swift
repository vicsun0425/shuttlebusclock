import XCTest
@testable import ShuttleBusClock

/// Unit tests for the schedule decision logic.
///
/// Every case runs against a calendar pinned to `Asia/Shanghai` so the results
/// don't depend on where the machine running the tests happens to be. Weekday
/// expectations are derived from the dates themselves rather than hard-coded,
/// so the tests validate the bit ordering instead of restating it.
@MainActor
final class ScheduleEvaluatorTests: XCTestCase {

    private var calendar: Calendar!
    private var evaluator: ScheduleEvaluator!

    override func setUp() async throws {
        try await super.setUp()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        calendar = cal
        evaluator = ScheduleEvaluator(calendar: cal)
    }

    override func tearDown() async throws {
        calendar = nil
        evaluator = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func makeStop(
        start: Int,
        end: Int,
        mask: Int = BusStop.allWeekdaysMask,
        enabled: Bool = true
    ) -> BusStop {
        let stop = BusStop(name: "测试站点", latitude: 39.9042, longitude: 116.4074)
        stop.isScheduleEnabled = enabled
        stop.effectiveWeekdayMask = mask
        stop.startMinute = start
        stop.endMinute = end
        return stop
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ hh: Int, _ mm: Int) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = hh; c.minute = mm
        return calendar.date(from: c)!
    }

    private func hm(_ hh: Int, _ mm: Int) -> Int { hh * 60 + mm }

    // MARK: - Window arithmetic (same day)

    func testWindowContainsStartMinute() {
        XCTAssertTrue(ScheduleEvaluator.isMinute(hm(9, 0), inStart: hm(9, 0), end: hm(18, 0)),
                      "窗口起点应包含在内")
    }

    func testWindowExcludesEndMinute() {
        XCTAssertFalse(ScheduleEvaluator.isMinute(hm(18, 0), inStart: hm(9, 0), end: hm(18, 0)),
                       "窗口终点是开区间,不应包含")
    }

    func testWindowContainsMiddleMinute() {
        XCTAssertTrue(ScheduleEvaluator.isMinute(hm(12, 0), inStart: hm(9, 0), end: hm(18, 0)))
    }

    func testWindowExcludesBeforeStart() {
        XCTAssertFalse(ScheduleEvaluator.isMinute(hm(8, 59), inStart: hm(9, 0), end: hm(18, 0)))
    }

    // MARK: - Window arithmetic (crosses midnight)

    func testMidnightCrossingLateNight() {
        XCTAssertTrue(ScheduleEvaluator.isMinute(hm(23, 30), inStart: hm(22, 0), end: hm(6, 0)))
    }

    func testMidnightCrossingEarlyMorning() {
        XCTAssertTrue(ScheduleEvaluator.isMinute(hm(2, 0), inStart: hm(22, 0), end: hm(6, 0)))
    }

    func testMidnightCrossingExcludesEnd() {
        XCTAssertFalse(ScheduleEvaluator.isMinute(hm(6, 0), inStart: hm(22, 0), end: hm(6, 0)))
    }

    func testMidnightCrossingExcludesJustBeforeStart() {
        XCTAssertFalse(ScheduleEvaluator.isMinute(hm(21, 59), inStart: hm(22, 0), end: hm(6, 0)))
    }

    func testMidnightCrossingIncludesStart() {
        XCTAssertTrue(ScheduleEvaluator.isMinute(hm(22, 0), inStart: hm(22, 0), end: hm(6, 0)))
    }

    // MARK: - Degenerate window

    func testEqualStartAndEndIsEmptyWindowNotAllDay() {
        // A mis-set picker must never silently become a 24/7 alarm.
        for minute in 0...1439 {
            XCTAssertFalse(
                ScheduleEvaluator.isMinute(minute, inStart: hm(8, 0), end: hm(8, 0)),
                "start == end 必须是空窗口,但 \(minute) 分被判为生效"
            )
        }
    }

    func testFullDayWindowIsExpressibleAsMidnightToEndOfDay() {
        // 00:00–23:59 is the widest the UI can express; it must cover almost
        // everything but still exclude its own exclusive end.
        XCTAssertTrue(ScheduleEvaluator.isMinute(hm(0, 0), inStart: 0, end: 1439))
        XCTAssertTrue(ScheduleEvaluator.isMinute(hm(23, 58), inStart: 0, end: 1439))
        XCTAssertFalse(ScheduleEvaluator.isMinute(hm(23, 59), inStart: 0, end: 1439))
    }

    // MARK: - Switch precedence

    func testMasterSwitchOffSuppressesEverything() {
        let stop = makeStop(start: 0, end: 1439)
        let decision = evaluator.decide(stop: stop, masterEnabled: false,
                                        at: date(2026, 8, 20, 12, 0))
        XCTAssertFalse(decision.isFiring)
        XCTAssertEqual(decision.reason, "总开关已关闭")
    }

    func testPerStopSwitchOffSuppresses() {
        let stop = makeStop(start: 0, end: 1439, enabled: false)
        let decision = evaluator.decide(stop: stop, masterEnabled: true,
                                        at: date(2026, 8, 20, 12, 0))
        XCTAssertFalse(decision.isFiring)
        XCTAssertEqual(decision.reason, "此站点未启用定时")
    }

    func testAllSwitchesOnAndInWindowFires() {
        let stop = makeStop(start: hm(7, 0), end: hm(10, 0))
        let decision = evaluator.decide(stop: stop, masterEnabled: true,
                                        at: date(2026, 8, 20, 8, 30))
        XCTAssertTrue(decision.isFiring, "全部条件满足时应触发,实际:\(decision.reason)")
    }

    func testInsideWindowButWrongWeekdaySuppresses() {
        let when = date(2026, 8, 20, 8, 30)
        let weekday = calendar.component(.weekday, from: when)
        // Everything selected except the day under test.
        let mask = BusStop.allWeekdaysMask & ~BusStop.weekdayBit(for: weekday)
        let stop = makeStop(start: hm(7, 0), end: hm(10, 0), mask: mask)

        let decision = evaluator.decide(stop: stop, masterEnabled: true, at: when)
        XCTAssertFalse(decision.isFiring)
        XCTAssertTrue(decision.reason.contains("未勾选"), "实际原因:\(decision.reason)")
    }

    func testRightWeekdayButOutsideWindowSuppresses() {
        let stop = makeStop(start: hm(7, 0), end: hm(10, 0))
        let decision = evaluator.decide(stop: stop, masterEnabled: true,
                                        at: date(2026, 8, 20, 10, 0))
        XCTAssertFalse(decision.isFiring)
        XCTAssertTrue(decision.reason.contains("时段"), "实际原因:\(decision.reason)")
    }

    // MARK: - Weekday bit ordering

    func testEachWeekdayBitMapsToItsOwnDay() {
        // Walk seven consecutive days. For each, select ONLY that day's bit and
        // assert it fires, then invert the mask and assert it doesn't. This
        // catches an off-by-one between `Calendar`'s 1-based weekday and the
        // 0-based bit position without hard-coding which date is which day.
        for offset in 0..<7 {
            let when = date(2026, 8, 17 + offset, 8, 30)
            let weekday = calendar.component(.weekday, from: when)
            let onlyThisDay = BusStop.weekdayBit(for: weekday)

            let selected = makeStop(start: hm(7, 0), end: hm(10, 0), mask: onlyThisDay)
            XCTAssertTrue(
                evaluator.decide(stop: selected, masterEnabled: true, at: when).isFiring,
                "只勾选 \(ScheduleEvaluator.weekdayName(weekday)) 时,该天应触发"
            )

            let deselected = makeStop(
                start: hm(7, 0), end: hm(10, 0),
                mask: BusStop.allWeekdaysMask & ~onlyThisDay
            )
            XCTAssertFalse(
                evaluator.decide(stop: deselected, masterEnabled: true, at: when).isFiring,
                "取消勾选 \(ScheduleEvaluator.weekdayName(weekday)) 时,该天不应触发"
            )
        }
    }

    func testOvernightWindowFiresAfterMidnightOnSelectedDay() {
        // 22:00–06:00 selected for the weekday the *alarm rings on* (02:00),
        // which is the day after the window opened. The evaluator judges the
        // instant, not the day the window started — assert that explicitly.
        let when = date(2026, 8, 20, 2, 0)
        let weekday = calendar.component(.weekday, from: when)
        let stop = makeStop(start: hm(22, 0), end: hm(6, 0),
                            mask: BusStop.weekdayBit(for: weekday))
        XCTAssertTrue(evaluator.decide(stop: stop, masterEnabled: true, at: when).isFiring)
    }

    // MARK: - Migration safety

    func testLegacyStopWithNoScheduleFieldsUsesDefaultsAndDoesNotCrash() {
        // Exactly how an existing on-device row deserialises: every new column nil.
        let legacy = BusStop(name: "老数据", latitude: 39.9042, longitude: 116.4074)

        XCTAssertNil(legacy.scheduleEnabled)
        XCTAssertNil(legacy.weekdayMask)
        XCTAssertNil(legacy.windowStartMinute)
        XCTAssertNil(legacy.windowEndMinute)

        XCTAssertFalse(legacy.isScheduleEnabled, "老数据默认不启用定时,不能凭空开始响")
        XCTAssertEqual(legacy.effectiveWeekdayMask, BusStop.weekdaysOnlyMask)
        XCTAssertEqual(legacy.startMinute, 7 * 60)
        XCTAssertEqual(legacy.endMinute, 10 * 60)

        let decision = evaluator.decide(stop: legacy, masterEnabled: true,
                                        at: date(2026, 8, 20, 8, 0))
        XCTAssertEqual(decision.reason, "此站点未启用定时")
    }

    func testMinuteSettersClampToValidRange() {
        let stop = makeStop(start: 0, end: 0)
        stop.startMinute = -30
        stop.endMinute = 9_999
        XCTAssertEqual(stop.startMinute, 0)
        XCTAssertEqual(stop.endMinute, 1439)
    }

    func testWeekdayToggleRoundTrips() {
        let stop = makeStop(start: 0, end: 1439, mask: 0)
        for weekday in 1...7 {
            XCTAssertFalse(stop.isWeekdaySelected(weekday))
            stop.setWeekday(weekday, selected: true)
            XCTAssertTrue(stop.isWeekdaySelected(weekday))
        }
        XCTAssertEqual(stop.effectiveWeekdayMask, BusStop.allWeekdaysMask)

        for weekday in 1...7 {
            stop.setWeekday(weekday, selected: false)
        }
        XCTAssertEqual(stop.effectiveWeekdayMask, 0)
    }
}
