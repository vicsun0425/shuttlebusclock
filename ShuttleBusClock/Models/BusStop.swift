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