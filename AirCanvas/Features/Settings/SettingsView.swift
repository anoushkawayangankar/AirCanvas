import SwiftUI

struct SettingsView: View {
    @Environment(OnboardingState.self) private var onboardingState

    var body: some View {
        List {
            Section("Help") {
                Button("Learn AirCanvas") { onboardingState.beginReplay() }
                    .accessibilityHint("Replays the first-run tutorial without changing any canvases")
                    .accessibilityIdentifier("settings.learnAirCanvas")
            }
        }
        .navigationTitle("Settings")
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
