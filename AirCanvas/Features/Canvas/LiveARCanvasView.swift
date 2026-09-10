import ARKit
import RealityKit
import SwiftUI
import UIKit

struct LiveARCanvasView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var experience: CanvasARExperience?
    private let project: CanvasProject
    private let repository: any CanvasProjectRepository
    private let recoveryMessage: String?

    init(
        project: CanvasProject,
        repository: any CanvasProjectRepository,
        recoveryMessage: String? = nil
    ) {
        self.project = project
        self.repository = repository
        self.recoveryMessage = recoveryMessage
        _experience = State(initialValue: nil)
    }

    var body: some View {
        Group {
            if let experience {
                CanvasRuntimeView(
                    experience: experience,
                    dismiss: dismiss,
                    scenePhase: scenePhase,
                    recoveryMessage: recoveryMessage
                )
            } else {
                ProgressView("Preparing Spatial Canvas")
                    .task { await prepareExperience(project: project, repository: repository) }
            }
        }
        .onDisappear {
            experience?.viewModel.canvasDidDisappear()
        }
    }

    private func prepareExperience(project: CanvasProject, repository: any CanvasProjectRepository) async {
        guard experience == nil else { return }
        let startedAt = ProcessInfo.processInfo.systemUptime
        var initialWorldMap: ARWorldMap?
        var relocalizationState: SpatialRelocalizationState = .none
        if project.spatialState != nil {
            relocalizationState = .preparing
            do {
                guard let data = try await repository.loadArchivedWorldMap(for: project) else {
                    relocalizationState = .failed(.spatialReferenceUnavailable)
                    experience = CanvasARExperience(project: project, repository: repository, initialWorldMap: nil, relocalizationState: relocalizationState)
                    return
                }
                initialWorldMap = try SpatialWorldMapCoder.unarchive(data)
            } catch {
                AppLogger.ar.error("Unable to prepare saved spatial reference: \(error.localizedDescription, privacy: .private(mask: .hash))")
                relocalizationState = .failed(.spatialReferenceUnavailable)
            }
        }
        experience = CanvasARExperience(project: project, repository: repository, initialWorldMap: initialWorldMap, relocalizationState: relocalizationState)
#if DEBUG
        AppLogger.performance.debug(
            "Canvas runtime prepared: duration=\(ProcessInfo.processInfo.systemUptime - startedAt, privacy: .public)s"
        )
#endif
    }
}

private struct CanvasRuntimeView: View {
    @Environment(OnboardingState.self) private var onboardingState
    let experience: CanvasARExperience
    let dismiss: DismissAction
    let scenePhase: ScenePhase
    let recoveryMessage: String?
    @State private var cursor = FingertipCursorModel()
    @State private var shareItem: CanvasExportShareItem?
    @State private var exportErrorMessage: String?
    @State private var isExporting = false

    var body: some View {
        ZStack {
            RealityKitARViewContainer(
                sceneController: experience.sceneController,
                touchHandler: experience.viewModel
            )
                .ignoresSafeArea(edges: .bottom)
            GeometryReader { proxy in
                Color.clear
                    .onAppear { cursor.updateViewportSize(proxy.size) }
                    .onChange(of: proxy.size) { _, size in cursor.updateViewportSize(size) }
                    .onChange(of: experience.viewModel.handTrackingState) { _, state in cursor.consume(state) }
                    .onChange(of: cursor.state) { _, state in experience.viewModel.updateSpatialFingertip(state) }
                if case .tracking(let point) = cursor.state {
                    Circle()
                        .strokeBorder(.white, lineWidth: 2)
                        .background(Circle().fill(experience.viewModel.pinchGestureState == .pinching ? .green.opacity(0.7) : .blue.opacity(0.55)))
                        .frame(width: 18, height: 18)
                        .position(point)
                        .accessibilityHidden(true)
                        .allowsHitTesting(false)
                }
            }
            .allowsHitTesting(false)

            VStack {
                CanvasARStatusView(
                    sessionState: experience.viewModel.sessionState,
                    retry: experience.viewModel.retrySession,
                    dismiss: dismiss
                )

                SpatialRelocalizationStatusView(
                    state: experience.viewModel.relocalizationState,
                    continueRelocalization: experience.viewModel.continueRelocalization,
                    openWithoutSpatialAlignment: experience.viewModel.openWithoutSpatialAlignment,
                    dismiss: dismiss
                )

                HandTrackingStatusView(state: experience.viewModel.handTrackingState)
                Text(experience.viewModel.pinchGestureState == .pinching ? "Pinching" : "Hand Open")
                    .font(.caption)
                    .padding(6)
                    .background(.regularMaterial, in: Capsule())

                Spacer()

                if let placementHint = experience.viewModel.placementHint {
                    PlacementHintView(message: placementHint)
                }

                if let recoveryMessage {
                    Text(recoveryMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                        .accessibilityLabel("Canvas recovery status")
                }

                if experience.viewModel.persistenceState == .saving || experience.viewModel.persistenceState == .dirty {
                    Text(experience.viewModel.persistenceState == .saving ? "Saving…" : "Saving changes…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Canvas save status")
                        .accessibilityValue(experience.viewModel.persistenceState == .saving ? "Saving" : "Changes waiting to save")
                }

                if experience.viewModel.persistenceState == .failed {
                    Button("Retry Save", action: experience.viewModel.retryProjectSave)
                        .buttonStyle(.borderedProminent)
                        .accessibilityHint("Retries saving the current canvas locally")
                }

                if !onboardingState.usesProductionSpatialRuntime {
                    CanvasBrushControlsView(
                        brushSettings: experience.viewModel.brushSettings,
                        selectColor: experience.viewModel.selectBrushColor,
                        updateThickness: experience.viewModel.updateBrushThickness,
                        canUndo: experience.viewModel.canUndo,
                        canRedo: experience.viewModel.canRedo,
                        undo: experience.viewModel.undoLastStroke,
                        redo: experience.viewModel.redoLastStroke,
                        canvasTool: experience.viewModel.canvasTool,
                        selectTool: experience.viewModel.selectTool,
                        hasSelectedStroke: experience.viewModel.selectedStrokeID != nil,
                        deleteSelectedStroke: experience.viewModel.deleteSelectedStroke,
                        transformScale: experience.viewModel.transformScale,
                        transformAngleDegrees: experience.viewModel.transformAngleDegrees,
                        beginScaleTransform: experience.viewModel.beginScaleTransform,
                        updateScaleTransform: experience.viewModel.updateScaleTransform,
                        beginRotationTransform: experience.viewModel.beginRotationTransform,
                        updateRotationTransform: experience.viewModel.updateRotationTransform,
                        endTransform: experience.viewModel.endStrokeTransform
                    )
                }
            }
            .padding()

            if onboardingState.usesProductionSpatialRuntime {
                OnboardingRuntimeGuidanceView(
                    readiness: onboardingState.spatialReadiness,
                    isHandReady: onboardingState.isHandReady,
                    step: onboardingState.step,
                    pinchState: onboardingState.pinchVerificationState,
                    continueFromHandCheck: onboardingState.continueFromHandCheck,
                    retryPinch: onboardingState.retryPinchVerification,
                    skipPinch: onboardingState.skipPinchVerification,
                    skipFirstStroke: {
                        experience.viewModel.cancelOnboardingFirstStroke()
                        onboardingState.skipFirstStroke()
                    },
                    retry: {
                        onboardingState.retrySpatialPreparation()
                        experience.viewModel.retrySession()
                    }
                )
            }
        }
        .onAppear {
            experience.viewModel.canvasDidAppear(isApplicationActive: scenePhase == .active)
            observeOnboardingRuntime()
            configureOnboardingPinchVerification()
        }
        .onDisappear {
            experience.viewModel.setOnboardingPinchVerification(active: false)
            experience.viewModel.setOnboardingCommittedStrokeObserver(nil)
        }
        .onChange(of: scenePhase) { _, newPhase in
            experience.viewModel.applicationActivityDidChange(isActive: newPhase == .active)
        }
        .onChange(of: experience.viewModel.sessionState) { _, _ in observeOnboardingRuntime() }
        .onChange(of: experience.viewModel.handTrackingState) { _, _ in observeOnboardingRuntime() }
        .onChange(of: experience.viewModel.spatialFingertipState) { _, _ in observeOnboardingRuntime() }
        .onChange(of: onboardingState.step) { _, _ in configureOnboardingPinchVerification() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        exportNativeDocument()
                    } label: {
                        Label("AirCanvas Document", systemImage: "doc.badge.arrow.up")
                    }
                    Button {
                        exportImage()
                    } label: {
                        Label("Image", systemImage: "photo")
                    }
                } label: {
                    if isExporting {
                        ProgressView()
                    } else {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                }
                .disabled(isExporting)
                .accessibilityLabel("Export canvas")
            }
        }
        .sheet(item: $shareItem) { item in
            CanvasShareSheet(items: [item.url]) {
                try? FileManager.default.removeItem(at: item.url)
                shareItem = nil
            }
        }
        .alert("Couldn’t Export Canvas", isPresented: exportErrorPresentationBinding) {
            Button("OK", role: .cancel) { exportErrorMessage = nil }
        } message: {
            Text(exportErrorMessage ?? "AirCanvas could not prepare this export.")
        }
    }

    private func exportNativeDocument() {
        let snapshot = experience.viewModel.projectSnapshotForExport()
        isExporting = true
        Task {
            do {
                let url = try await Task.detached(priority: .utility) {
                    try AirCanvasDocumentExporter.writeTemporaryDocument(for: snapshot)
                }.value
                shareItem = CanvasExportShareItem(url: url)
            } catch {
                exportErrorMessage = UserFacingErrorMessage.export(error)
            }
            isExporting = false
        }
    }

    private func exportImage() {
        let snapshot = experience.viewModel.projectSnapshotForExport()
        isExporting = true
        Task {
            do {
                shareItem = CanvasExportShareItem(url: try CanvasImageExporter.writeTemporaryPNG(for: snapshot))
            } catch {
                exportErrorMessage = UserFacingErrorMessage.export(error)
            }
            isExporting = false
        }
    }

    private var exportErrorPresentationBinding: Binding<Bool> {
        Binding(
            get: { exportErrorMessage != nil },
            set: { if !$0 { exportErrorMessage = nil } }
        )
    }

    private func observeOnboardingRuntime() {
        onboardingState.observeProductionRuntime(
            sessionState: experience.viewModel.sessionState,
            handState: experience.viewModel.handTrackingState,
            fingertipState: experience.viewModel.spatialFingertipState
        )
    }

    private func configureOnboardingPinchVerification() {
        let isPinchCheck = onboardingState.step == .pinchCheck
        experience.viewModel.setOnboardingPinchVerification(
            active: isPinchCheck,
            eventHandler: isPinchCheck ? { event in
                onboardingState.observeProductionPinchEvent(event)
            } : nil
        )
        experience.viewModel.setOnboardingCommittedStrokeObserver(
            onboardingState.step == .firstStroke ? { _, canvasID in
                onboardingState.observeCommittedOnboardingStroke(in: canvasID)
            } : nil
        )
        if onboardingState.step == .firstStroke {
            experience.viewModel.selectTool(.draw)
        }
    }
}

private struct OnboardingRuntimeGuidanceView: View {
    let readiness: SpatialReadinessState
    let isHandReady: Bool
    let step: OnboardingStep
    let pinchState: PinchVerificationState
    let continueFromHandCheck: () -> Void
    let retryPinch: () -> Void
    let skipPinch: () -> Void
    let skipFirstStroke: () -> Void
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            if step == .pinchCheck {
                pinchGuidance
            } else if step == .firstStroke {
                firstStrokeGuidance
            } else {
            switch readiness {
            case .preparing:
                guidance(symbol: "arkit", title: "Preparing your space…", text: "Move your iPhone slowly to map your space.")
            case .limited(let limitation):
                guidance(symbol: "iphone.radiowaves.left.and.right", title: "Keep Mapping", text: limitation.guidance)
            case .interrupted:
                guidance(symbol: "pause.circle", title: "Spatial Tracking Interrupted", text: "AirCanvas will continue when tracking is available again.")
            case .failed(let message):
                guidance(symbol: "exclamationmark.triangle", title: "Spatial Tracking Unavailable", text: message)
                Button("Try Again", action: retry).buttonStyle(.borderedProminent)
            case .ready:
                guidance(symbol: isHandReady ? "hand.raised.fill" : "hand.raised", title: isHandReady ? "Hand detected" : "Hold one hand where the camera can see it.", text: isHandReady ? "Your spatial cursor is ready." : "Keep your index fingertip visible and use good lighting.")
                if isHandReady {
                    Button("Continue", action: continueFromHandCheck)
                        .buttonStyle(.borderedProminent)
                        .accessibilityLabel("Continue to pinch gesture check")
                }
            }
            }
        }
        .padding()
        .frame(maxWidth: 420)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .padding()
        .accessibilityElement(children: .contain)
    }

    private func guidance(symbol: String, title: String, text: String) -> some View {
        VStack(spacing: 6) {
            Label(title, systemImage: symbol).font(.headline)
            Text(text).font(.subheadline).multilineTextAlignment(.center).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var pinchGuidance: some View {
        switch pinchState {
        case .waitingForPinch:
            guidance(symbol: "hand.pinch", title: "Pinch to Draw", text: "Pinch your thumb and index finger.")
        case .waitingForRelease:
            guidance(symbol: "hand.pinch.fill", title: "Pinch detected", text: "Great — now release.")
        case .completed:
            guidance(symbol: "checkmark.circle.fill", title: "Gesture recognized", text: "Continuing…")
        }
        HStack {
            Button("Try Again", action: retryPinch).buttonStyle(.bordered)
            Button("Skip", action: skipPinch).buttonStyle(.bordered)
        }
        .accessibilityElement(children: .contain)
    }

    private var firstStrokeGuidance: some View {
        VStack(spacing: 10) {
            guidance(symbol: "hand.draw.fill", title: "Make Your First Stroke", text: "Pinch and move your hand to draw.")
            Text("This creates real content in your canvas.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Skip", action: skipFirstStroke)
                .buttonStyle(.bordered)
                .accessibilityLabel("Skip first stroke coaching")
        }
    }
}

private struct CanvasExportShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct CanvasShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    let completed: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            DispatchQueue.main.async {
                completed()
            }
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

@MainActor
private final class CanvasARExperience {
    let sceneController: RealityKitSceneController
    let viewModel: CanvasARViewModel

    init(project: CanvasProject, repository: any CanvasProjectRepository, initialWorldMap: ARWorldMap?, relocalizationState: SpatialRelocalizationState) {
        let sessionService = ARSessionService(initialWorldMap: initialWorldMap)
        sceneController = RealityKitSceneController(session: sessionService.session)
        let handTrackingCoordinator = HandTrackingCoordinator()
        sessionService.setCameraFrameHandler { frame in
            handTrackingCoordinator.submit(
                pixelBuffer: frame.pixelBuffer,
                orientation: frame.orientation,
                timestamp: frame.timestamp
            )
        }
        let raycastService = SpatialRaycastService(arView: sceneController.makeARView())
        let drawingEngine = DrawingEngine(completedStrokes: project.strokes)
        viewModel = CanvasARViewModel(
            sessionService: sessionService,
            raycastService: raycastService,
            drawingEngine: drawingEngine,
            strokeRenderer: sceneController.makeStrokeRenderer(),
            brushSettings: .defaultSettings,
            project: project,
            repository: repository,
            handTrackingCoordinator: handTrackingCoordinator,
            spatialCursorRenderer: sceneController,
            relocalizationState: relocalizationState
        )
    }
}

private struct HandTrackingStatusView: View {
    let state: HandTrackingState

    var body: some View {
        Text(state.statusText)
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .accessibilityLabel("Hand tracking status")
            .accessibilityValue(state.statusText)
    }
}

private struct RealityKitARViewContainer: UIViewRepresentable {
    let sceneController: RealityKitSceneController
    let touchHandler: any CanvasTouchInputHandling

    func makeCoordinator() -> Coordinator {
        Coordinator(handler: touchHandler)
    }

    func makeUIView(context: Context) -> ARView {
        let arView = sceneController.makeARView()
        context.coordinator.inputAdapter.install(on: arView)
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject {
        let inputAdapter: CanvasTouchInputAdapter

        init(handler: any CanvasTouchInputHandling) {
            inputAdapter = CanvasTouchInputAdapter(handler: handler)
        }
    }
}

private struct CanvasARStatusView: View {
    let sessionState: ARSessionState
    let retry: () -> Void
    let dismiss: DismissAction

    var body: some View {
        switch sessionState {
        case .running(let trackingState):
            if let guidance = trackingState.guidance {
                statusBanner(guidance)
            }
        case .interrupted:
            statusBanner("Spatial tracking is temporarily interrupted.")
        case .failed(let failure):
            failureCard(failure)
        case .idle:
            EmptyView()
        }
    }

    @ViewBuilder
    private func statusBanner(_ message: String) -> some View {
        Text(message)
            .font(.subheadline)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.regularMaterial, in: Capsule())
            .accessibilityLabel("Spatial tracking status")
            .accessibilityValue(message)
    }

    private func failureCard(_ failure: ARSessionFailure) -> some View {
        VStack(spacing: 12) {
            Label(failure.title, systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
            Text(failure.message)
                .multilineTextAlignment(.center)
            HStack {
                Button("Try Again", action: retry)
                    .buttonStyle(.borderedProminent)
                Button("Return Home") {
                    dismiss()
                }
                    .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .contain)
    }
}

private struct SpatialRelocalizationStatusView: View {
    let state: SpatialRelocalizationState
    let continueRelocalization: () -> Void
    let openWithoutSpatialAlignment: () -> Void
    let dismiss: DismissAction

    var body: some View {
        switch state {
        case .none, .localized, .fallback:
            EmptyView()
        case .preparing, .scanning:
            statusCard(state.guidance ?? "Finding your canvas.", actions: false)
        case .failed:
            VStack(spacing: 12) {
                Text(state.guidance ?? "The canvas could not be located.")
                    .multilineTextAlignment(.center)
                HStack {
                    if state == .failed(.notFound) {
                        Button("Keep Scanning", action: continueRelocalization)
                            .buttonStyle(.bordered)
                    }
                    Button("Open Without Spatial Alignment", action: openWithoutSpatialAlignment)
                        .buttonStyle(.borderedProminent)
                    Button("Return Home") { dismiss() }
                        .buttonStyle(.bordered)
                }
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .accessibilityElement(children: .contain)
        }
    }

    private func statusCard(_ message: String, actions: Bool) -> some View {
        Text(message)
            .font(.subheadline)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.regularMaterial, in: Capsule())
            .accessibilityLabel("Spatial canvas restoration status")
            .accessibilityValue(message)
    }
}

private struct PlacementHintView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.subheadline)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.regularMaterial, in: Capsule())
            .accessibilityLabel("Placement guidance")
            .accessibilityValue(message)
    }
}
