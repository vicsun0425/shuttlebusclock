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
                ActiveAlarmView()
                    .transition(.opacity)
            case .armed:
                ArmedTripView()
                    .transition(.opacity)
            case .idle:
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