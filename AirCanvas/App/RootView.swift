import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(OnboardingState.self) private var onboardingState

    var body: some View {
        @Bindable var appState = appState

        Group {
            if onboardingState.requiresOnboarding {
                if onboardingState.usesProductionSpatialRuntime {
                    OnboardingSpatialRuntimeView()
                } else {
                    OnboardingView()
                }
            } else {
                NavigationStack(path: $appState.navigationPath) {
                    HomeView()
                        .navigationDestination(for: AppRoute.self) { route in
                            destination(for: route)
                        }
                }
            }
        }
        .alert(item: $appState.presentedError) { error in
            Alert(
                title: Text(error.title),
                message: Text(error.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        switch route {
        case .canvas(let launch):
            SpatialCanvasAccessView(launch: launch)
        case .myCanvases:
            MyCanvasesView(repository: appState.projectRepository)
        case .settings:
            SettingsView()
        }
    }
}

#Preview {
    RootView()
        .environment(AppState())
        .environment(OnboardingState(defaults: .previewCompletedOnboarding))
}
