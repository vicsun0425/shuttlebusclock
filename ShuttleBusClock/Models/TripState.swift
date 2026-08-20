import Foundation
import SwiftData

/// State machine for the current trip.
///
/// - `idle`: no trip armed, location services may still be tracking passively.
/// - `armed`: a trip is armed, region + continuous location monitoring active.
/// - `alerting`: alarm is firing (distance crossed threshold), UI is locked.
enum TripState: Equatable {
    case idle
    case armed(stopID: PersistentIdentifier)
    case alerting(stopID: PersistentIdentifier)

    var stopID: PersistentIdentifier? {
        switch self {
        case .idle:                  return nil
        case .armed(let id):         return id
        case .alerting(let id):      return id
        }
    }

    var isActive: Bool {
        switch self {
        case .idle: return false
        default:    return true
        }
    }
}