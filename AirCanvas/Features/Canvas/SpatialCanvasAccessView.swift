import SwiftUI
import UIKit

struct SpatialCanvasAccessView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel: SpatialCanvasAccessViewModel
    @State private var projectState: CanvasProjectAccessState = .waiting

    private let launch: CanvasLaunch

    init(
        launch: CanvasLaunch = .new,
        viewModel: SpatialCanvasAccessViewModel = SpatialCanvasAccessViewModel()
    ) {
        self.launch = launch
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .checking:
                ProgressView("Preparing Spatial Canvas")
                    .accessibilityLabel("Preparing spatial canvas")
            case .readyForCanvas:
                projectDestination
            case .cameraAccessRequired:
                CameraAccessRequiredView()
            case .cameraAccessRestricted:
                CameraAccessRestrictedView()
            case .unsupportedDevice:
                UnsupportedDeviceView()
            }
        }
        .navigationTitle("New Canvas")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.prepareForCanvas()
        }
        .task(id: viewModel.state == .readyForCanvas) {
            guard viewModel.state == .readyForCanvas else {
                return
            }
            await resolveProjectIfNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else {
                return
            }

            viewModel.refreshAfterApplicationBecomesActive()
        }
    }

    @ViewBuilder
    private var projectDestination: some View {
        switch projectState {
        case .waiting, .loading:
            ProgressView("Opening Canvas")
                .accessibilityLabel("Opening Canvas")
        case .ready(let project, let recoveryMessage):
            LiveARCanvasView(
                project: project,
                repository: appState.projectRepository,
                recoveryMessage: recoveryMessage
            )
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn’t Open Canvas", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") {
                    projectState = .waiting
                    Task { await resolveProjectIfNeeded() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func resolveProjectIfNeeded() async {
        guard case .waiting = projectState else {
            return
        }
        projectState = .loading

        do {
            switch launch {
            case .new:
                projectState = .ready(
                    try await appState.projectRepository.createProject(named: "Untitled Canvas"),
                    recoveryMessage: nil
                )
            case .existing(let id):
                let project = try await appState.projectRepository.loadProject(id: id)
                let recoveryMessage = await appState.projectRepository.consumeRecoveryNotice(for: id)
                projectState = .ready(project, recoveryMessage: recoveryMessage)
            }
        } catch {
            AppLogger.persistence.error("Canvas project access failed: \(error.localizedDescription, privacy: .private(mask: .hash))")
            projectState = .failed(UserFacingErrorMessage.canvasOpen(error))
        }
    }
}

private enum CanvasProjectAccessState: Equatable {
    case waiting
    case loading
    case ready(CanvasProject, recoveryMessage: String?)
    case failed(String)
}

private struct CameraAccessRequiredView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openURL) private var openURL

    var body: some View {
        ContentUnavailableView {
            Label("Camera Access Required", systemImage: "camera.fill")
        } description: {
            Text("AirCanvas requires camera access to understand the surrounding space for spatial drawing.")
        } actions: {
            Button("Open Settings") {
                openAppSettings()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityHint("Opens AirCanvas settings in the Settings app")
        }
    }

    private func openAppSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else {
            AppLogger.permissions.error("Unable to construct the application settings URL")
            appState.present(.operationFailed)
            return
        }

        openURL(settingsURL) { accepted in
            guard !accepted else {
                return
            }

            AppLogger.permissions.error("The system did not open the application settings URL")
            appState.present(.operationFailed)
        }
    }
}

private struct CameraAccessRestrictedView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ContentUnavailableView {
            Label("Camera Access Is Restricted", systemImage: "camera.badge.ellipsis")
        } description: {
            Text("Camera access is restricted by device or account settings. Contact the device administrator or adjust the applicable restrictions to use spatial drawing.")
        } actions: {
            Button("Return Home") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

private struct UnsupportedDeviceView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ContentUnavailableView {
            Label("AirCanvas Spatial Drawing Isn't Supported on This Device", systemImage: "iphone.slash")
        } description: {
            Text("The spatial canvas requires supported AR world-tracking capabilities. You can continue using other parts of AirCanvas.")
        } actions: {
            Button("Return Home") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

#Preview("Camera Access Required") {
    NavigationStack {
        SpatialCanvasAccessView(
            viewModel: SpatialCanvasAccessViewModel(
                cameraPermissionService: PreviewCameraPermissionService(authorization: .denied),
                capabilityService: PreviewCapabilityService(capability: .supported)
            )
        )
    }
    .environment(AppState())
}

private struct PreviewCameraPermissionService: CameraPermissionProviding {
    let authorization: CameraAuthorization

    func authorizationStatus() -> CameraAuthorization {
        authorization
    }

    func requestAccess() async -> CameraAuthorization {
        authorization
    }
}

private struct PreviewCapabilityService: SpatialCanvasCapabilityChecking {
    let capability: SpatialCanvasCapability

    func spatialCanvasCapability() -> SpatialCanvasCapability {
        capability
    }
}
