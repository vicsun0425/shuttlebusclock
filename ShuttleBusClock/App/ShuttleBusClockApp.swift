import SwiftUI
import SwiftData

@main
struct ShuttleBusClockApp: App {
    /// Shared managers. Owned by the App scene and injected via `.environment`.
    @State private var locationManager: LocationManager
    @State private var alarmManager: AlarmManager

    init() {
        // Construct + wire dependencies eagerly so the LocationManager can
        // hand off to AlarmManager the moment a region threshold is crossed.
        let loc = LocationManager()
        let alarm = AlarmManager()
        loc.alarmManager = alarm
        _locationManager = State(initialValue: loc)
        _alarmManager = State(initialValue: alarm)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(PersistenceController.shared)
        }
        .environment(locationManager)
        .environment(alarmManager)
    }
}