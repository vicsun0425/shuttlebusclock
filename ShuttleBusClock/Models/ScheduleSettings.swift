import Foundation

/// The app-wide master switch for scheduled monitoring.
///
/// Deliberately kept out of SwiftData: it's a single global preference that
/// belongs to no particular stop, and putting it in the model would mean
/// another schema change for one Bool.
enum ScheduleSettings {
    private static let masterEnabledKey = "schedule.masterEnabled"

    /// Posted after `masterEnabled` changes so `LocationManager` can
    /// re-register (or tear down) the persistent regions.
    static let masterEnabledDidChange = Notification.Name("ScheduleSettings.masterEnabledDidChange")

    static var masterEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: masterEnabledKey) }
        set {
            guard newValue != masterEnabled else { return }
            UserDefaults.standard.set(newValue, forKey: masterEnabledKey)
            NotificationCenter.default.post(name: masterEnabledDidChange, object: newValue)
        }
    }
}
