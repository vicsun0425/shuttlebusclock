import SwiftUI
import SwiftData
import CoreLocation

/// Root view. Switches between list / armed / alerting / onboarding based on
/// the current `LocationManager.tripState` and authorization.
struct ContentView: View {
    @Environment(LocationManager.self) private var locationManager

    var body: some View {
        ZStack {
            switch locationManager.tripState {
            case .alerting:
                // The alarm is the one screen that *should* take over — its
                // whole job is to be impossible to ignore.
                ActiveAlarmView()
                    .transition(.opacity)
            case .armed, .idle:
                // An armed trip no longer hijacks the app. StopListView raises
                // the trip view as a dismissible sheet, so "go back" and "end
                // the trip" stay separate actions.
                if needsOnboarding {
                    PermissionOnboardingView()
                } else {
                    StopListView()
                }
            }
        }
        .animation(.easeInOut, value: locationManager.tripState)
    }

    /// First-run users (no When-In-Use yet) see the onboarding flow first.
    private var needsOnboarding: Bool {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            return true
        default:
            return false
        }
    }
}

#Preview {
    ContentView()
        .environment(LocationManager())
        .environment(AlarmManager())
        .modelContainer(PersistenceController.preview)
}