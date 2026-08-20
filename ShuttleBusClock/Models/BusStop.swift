import Foundation
import SwiftData
import CoreLocation

/// A saved shuttle bus stop the user wants to be woken up before reaching.
@Model
final class BusStop {
    /// Display name (e.g. "公司", "家").
    var name: String

    /// Latitude of the destination.
    var latitude: Double

    /// Longitude of the destination.
    var longitude: Double

    /// Trigger radius in meters. Default 3000 (3 km).
    /// Apple recommends keeping regions reasonably sized; user can override.
    var radius: Double

    /// Sort order for the list view.
    var sortIndex: Int

    /// Creation timestamp.
    var createdAt: Date

    // MARK: - Scheduled monitoring
    //
    // These are all Optional on purpose. `PersistenceController` builds a plain
    // `Schema([BusStop.self])` with no migration plan, so adding a non-optional
    // property would fail to open an existing store and hit its `fatalError`.
    // Nullable columns are what SwiftData's lightweight migration handles for
    // free. Everything above the model reads the computed accessors below, which
    // fill in defaults, so the Optionals never leak out.

    /// Whether this stop is monitored around the clock on a schedule.
    var scheduleEnabled: Bool?

    /// 7-bit weekday bitmask. Sunday is bit 0, matching `weekdayBit(for:)`.
    var weekdayMask: Int?

    /// Window start, minutes since local midnight (0...1439).
    var windowStartMinute: Int?

    /// Window end, minutes since local midnight (0...1439). Exclusive.
    var windowEndMinute: Int?

    init(
        name: String,
        latitude: Double,
        longitude: Double,
        radius: Double = 3000,
        sortIndex: Int = 0
    ) {
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.radius = radius
        self.sortIndex = sortIndex
        self.createdAt = Date()
    }

    /// Convenience: destination as a `CLLocation`.
    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }

    /// Convenience: destination as a `CLLocationCoordinate2D`.
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

// MARK: - Schedule accessors

extension BusStop {
    /// Every day selected.
    static let allWeekdaysMask = 0b1111111
    /// Mon–Fri, the common commute pattern. Sunday is bit 0, so Mon–Fri is bits 1–5.
    static let weekdaysOnlyMask = 0b0111110

    /// Bit position for a `Calendar` weekday component (1 = Sunday ... 7 = Saturday).
    static func weekdayBit(for calendarWeekday: Int) -> Int {
        1 << (calendarWeekday - 1)
    }

    var isScheduleEnabled: Bool {
        get { scheduleEnabled ?? false }
        set { scheduleEnabled = newValue }
    }

    var effectiveWeekdayMask: Int {
        get { weekdayMask ?? BusStop.weekdaysOnlyMask }
        set { weekdayMask = newValue & BusStop.allWeekdaysMask }
    }

    var startMinute: Int {
        get { windowStartMinute ?? (7 * 60) }
        set { windowStartMinute = min(max(newValue, 0), 1439) }
    }

    var endMinute: Int {
        get { windowEndMinute ?? (10 * 60) }
        set { windowEndMinute = min(max(newValue, 0), 1439) }
    }

    /// A window whose end is not strictly after its start wraps past midnight —
    /// except when they're equal, which `ScheduleEvaluator` treats as empty.
    var crossesMidnight: Bool { endMinute < startMinute }

    func isWeekdaySelected(_ calendarWeekday: Int) -> Bool {
        effectiveWeekdayMask & BusStop.weekdayBit(for: calendarWeekday) != 0
    }

    func setWeekday(_ calendarWeekday: Int, selected: Bool) {
        let bit = BusStop.weekdayBit(for: calendarWeekday)
        effectiveWeekdayMask = selected
            ? effectiveWeekdayMask | bit
            : effectiveWeekdayMask & ~bit
    }
}

extension BusStop {
    /// Suggested radius presets the user can pick from in the UI.
    enum RadiusPreset: Double, CaseIterable, Identifiable {
        case oneKm    = 1000
        case threeKm  = 3000
        case fiveKm   = 5000
        case tenKm    = 10000

        var id: Double { rawValue }

        var label: String {
            switch self {
            case .oneKm:   return "1 km"
            case .threeKm: return "3 km"
            case .fiveKm:  return "5 km"
            case .tenKm:   return "10 km"
            }
        }

        func matches(radius: Double) -> Bool {
            abs(self.rawValue - radius) < 1
        }
    }
}