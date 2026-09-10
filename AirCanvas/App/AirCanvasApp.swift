import SwiftUI

@main
struct AirCanvasApp: App {
    @State private var appState: AppState
    @State private var onboardingState: OnboardingState

    init() {
        _appState = State(initialValue: AppState())
        _onboardingState = State(initialValue: OnboardingState(defaults: LaunchDefaults.onboardingDefaults()))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .environment(onboardingState)
        }
    }
}

private enum LaunchDefaults {
    static func onboardingDefaults() -> UserDefaults {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["AIRCANVAS_UI_TESTING"] == "1" else {
            return .standard
        }

        guard let argumentIndex = ProcessInfo.processInfo.arguments.firstIndex(of: "-AirCanvasOnboardingCompleted"),
              ProcessInfo.processInfo.arguments.indices.contains(argumentIndex + 1) else {
            return .standard
        }

        let suiteName = "AirCanvas.UITests.Onboarding"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        let completed = ProcessInfo.processInfo.arguments[argumentIndex + 1] == "YES"
        if completed {
            defaults.set(true, forKey: OnboardingState.completionKey)
            defaults.set(OnboardingState.currentVersion, forKey: OnboardingState.completionVersionKey)
        } else {
            defaults.removeObject(forKey: OnboardingState.completionKey)
            defaults.removeObject(forKey: OnboardingState.completionVersionKey)
            defaults.removeObject(forKey: OnboardingState.onboardingCanvasIdentifierKey)
        }
        return defaults
        #else
        return .standard
        #endif
    }
}
