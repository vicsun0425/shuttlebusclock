import Foundation

/// Decides whether an armed schedule should actually fire right now.
///
/// Pure and injectable — production and tests run the exact same code, so there
/// is no seam that can drift. The `Calendar` is injected because every decision
/// is local-time based and tests need a fixed timezone.
struct ScheduleEvaluator {

    enum Decision: Equatable {
        /// Schedule allows the alarm. Carries a human-readable reason.
        case fire(String)
        /// Schedule blocks the alarm. The reason is shown in the UI so the user
        /// can tell a working switch from a broken one.
        case suppress(String)

        var isFiring: Bool {
            if case .fire = self { return true }
            return false
        }

        var reason: String {
            switch self {
            case .fire(let r), .suppress(let r): return r
            }
        }
    }

    let calendar: Calendar

    /// Uses the device's current calendar — and therefore its *current*
    /// timezone, resolved at decision time rather than at registration time,
    /// so travelling across timezones can't leave a stale rule behind.
    static var current: ScheduleEvaluator { ScheduleEvaluator(calendar: .current) }

    func decide(stop: BusStop, masterEnabled: Bool, at date: Date) -> Decision {
        guard masterEnabled else {
            return .suppress("总开关已关闭")
        }
        guard stop.isScheduleEnabled else {
            return .suppress("此站点未启用定时")
        }

        let weekday = calendar.component(.weekday, from: date)
        guard stop.isWeekdaySelected(weekday) else {
            return .suppress("\(Self.weekdayName(weekday))未勾选")
        }

        let minute = calendar.component(.hour, from: date) * 60
                   + calendar.component(.minute, from: date)
        guard Self.isMinute(minute, inStart: stop.startMinute, end: stop.endMinute) else {
            return .suppress("不在时段 \(Self.timeString(stop.startMinute))–\(Self.timeString(stop.endMinute)) 内")
        }

        return .fire("在生效时段内")
    }

    /// Whether `m` falls in `[start, end)`, handling windows that wrap midnight.
    ///
    /// - `09:00–18:00` contains 09:00, excludes 18:00.
    /// - `22:00–06:00` wraps: contains 23:30 and 02:00, excludes 06:00 and 21:59.
    /// - `start == end` is an *empty* window, not an all-day one. Treating it as
    ///   all-day would silently turn a mis-set picker into a 24/7 alarm.
    static func isMinute(_ m: Int, inStart s: Int, end e: Int) -> Bool {
        if s == e { return false }
        if s < e { return m >= s && m < e }
        return m >= s || m < e
    }

    // MARK: - Formatting

    static func timeString(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }

    /// `calendarWeekday` is 1 = Sunday ... 7 = Saturday, matching `Calendar`.
    static func weekdayName(_ calendarWeekday: Int) -> String {
        ["周日", "周一", "周二", "周三", "周四", "周五", "周六"][calendarWeekday - 1]
    }
}
