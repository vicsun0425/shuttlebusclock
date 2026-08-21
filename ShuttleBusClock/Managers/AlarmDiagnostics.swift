import Foundation

/// A tiny persistent breadcrumb trail for alarm attempts.
///
/// Exists because the failure this was written for — the alarm not going off
/// while the user was asleep — left no evidence at all. `AlarmManager` used to
/// `print` its errors, which goes nowhere on a device, and in-memory state dies
/// with the process. These entries survive an app kill so the next failure can
/// actually be diagnosed instead of guessed at.
enum AlarmDiagnostics {
    private static let key = "alarm.diagnostics"
    private static let limit = 60

    struct Entry: Codable, Identifiable {
        let id: UUID
        let at: Date
        let event: String
        let detail: String

        init(event: String, detail: String) {
            self.id = UUID()
            self.at = Date()
            self.event = event
            self.detail = detail
        }
    }

    static func record(_ event: String, _ detail: String = "") {
        var entries = all()
        entries.insert(Entry(event: event, detail: detail), at: 0)
        if entries.count > limit { entries.removeLast(entries.count - limit) }
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func all() -> [Entry] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let entries = try? JSONDecoder().decode([Entry].self, from: data)
        else { return [] }
        return entries
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
