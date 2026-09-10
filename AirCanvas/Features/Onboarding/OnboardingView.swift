import SwiftUI
import UIKit

struct OnboardingView: View {
    @Environment(OnboardingState.self) private var onboardingState
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 32)
                message
                controls
            }
            .frame(maxWidth: 520)
            .padding(24)
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { onboardingState.refreshPermission() } }
    }

    @ViewBuilder private var message: some View {
        switch onboardingState.step {
        case .welcome: Message(symbol: "scribble.variable", title: "Spatial Drawing", text: "AirCanvas lets you draw and edit artwork in physical space. Your work stays organized in My Canvases, and touch controls remain available for editing.")
        case .interactionBasics: Message(symbol: "hand.draw", title: "Draw, Select, Erase", text: "In Draw, point, pinch, and move. In Select, pinch a stroke to move it. In Erase, pinch once to remove a highlighted stroke. Undo is always available.")
        case .cameraEducation: Message(symbol: "camera.fill", title: "Camera Access", text: "AirCanvas uses the camera to understand your hand position and place drawings in your surroundings. Camera frames stay on your device.")
        case .cameraDenied: Message(symbol: "camera.fill.badge.ellipsis", title: "Camera Access Required", text: "AirCanvas needs camera access for spatial drawing and hand tracking. You can enable it in Settings.")
        case .cameraRestricted: Message(symbol: "lock.fill", title: "Camera Access Restricted", text: "Camera access is restricted on this device. AirCanvas cannot request access on your behalf.")
        case .unsupportedDevice: Message(symbol: "iphone.slash", title: "Spatial Drawing Isn’t Supported", text: "AirCanvas requires a compatible iPhone with AR world tracking. You can still manage saved canvases and exported documents where available.")
        case .spatialPreparation, .handCheck, .pinchCheck, .firstStroke, .complete: EmptyView()
        }
    }

    @ViewBuilder private var controls: some View {
        switch onboardingState.step {
        case .welcome, .interactionBasics:
            HStack { if onboardingState.step == .interactionBasics { Button("Back", action: onboardingState.goBack) }; Spacer(); Button("Continue") { Task { await onboardingState.advance() } }.buttonStyle(.borderedProminent) }
        case .cameraEducation:
            HStack { Button("Back", action: onboardingState.goBack); Spacer(); Button(onboardingState.isRequestingCamera ? "Requesting Camera…" : "Continue") { Task { await onboardingState.advance() } }.buttonStyle(.borderedProminent).disabled(onboardingState.isRequestingCamera) }
        case .cameraDenied:
            Button("Open Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } }.buttonStyle(.borderedProminent).accessibilityHint("Opens AirCanvas settings so camera access can be enabled")
        case .cameraRestricted, .unsupportedDevice:
            Button("Continue to My Canvases", action: onboardingState.completeOnboarding).buttonStyle(.borderedProminent)
        case .spatialPreparation, .handCheck, .pinchCheck, .firstStroke, .complete: EmptyView()
        }
    }
}

/// Hosts the normal, single production canvas runtime while onboarding needs
/// live AR and hand state. It creates one durable first canvas only after the
/// user has passed capability and camera authorization; subsequent renders keep
/// the same in-memory project, so stage changes cannot create parallel sessions.
struct OnboardingSpatialRuntimeView: View {
    @Environment(AppState.self) private var appState
    @Environment(OnboardingState.self) private var onboardingState
    @Environment(\.scenePhase) private var scenePhase
    @State private var project: CanvasProject?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let project {
                LiveARCanvasView(project: project, repository: appState.projectRepository)
            } else if let message = errorMessage {
                ContentUnavailableView {
                    Label("Couldn’t Prepare Your First Canvas", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") {
                        errorMessage = nil
                        Task { await loadInitialProject() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                ProgressView("Preparing Spatial Canvas")
                    .task { await loadInitialProject() }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                onboardingState.refreshPermission()
            }
        }
    }

    private func loadInitialProject() async {
        guard project == nil else { return }
        do {
            if let id = onboardingState.onboardingCanvasID {
                project = try await appState.projectRepository.loadProject(id: id)
            } else {
                // Replay or restored application state may already have work.
                // Reuse the repository's deterministic library ordering rather
                // than creating an uncontrolled additional tutorial canvas.
                if let existing = try await appState.projectRepository.listProjects().first {
                    let loaded = try await appState.projectRepository.loadProject(id: existing.id)
                    onboardingState.rememberOnboardingCanvas(id: loaded.id)
                    project = loaded
                } else {
                    let created = try await appState.projectRepository.createProject(named: "My First Canvas")
                    onboardingState.rememberOnboardingCanvas(id: created.id)
                    project = created
                }
            }
        } catch {
            errorMessage = "AirCanvas could not create your first canvas. Please try again."
            AppLogger.persistence.error("Onboarding canvas creation failed: \(error.localizedDescription, privacy: .private(mask: .hash))")
        }
    }
}

private struct Message: View {
    let symbol: String; let title: String; let text: String
    var body: some View {
        Image(systemName: symbol).font(.system(size: 56, weight: .medium)).foregroundStyle(.tint).accessibilityHidden(true)
        Text(title).font(.largeTitle.bold()).multilineTextAlignment(.center).accessibilityAddTraits(.isHeader)
        Text(text).font(.body).multilineTextAlignment(.center).foregroundStyle(.secondary)
    }
}

#Preview {
    OnboardingView()
        .environment(OnboardingState(defaults: .previewCompletedOnboarding))
}
