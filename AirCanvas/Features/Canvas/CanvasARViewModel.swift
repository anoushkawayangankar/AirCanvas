import CoreGraphics
import Foundation
import Observation
import simd
import UIKit

enum CanvasProjectPersistenceState: Equatable {
    case clean
    case dirty
    case saving
    case failed
}
enum DrawingInputSource: Equatable { case none, touch, hand }

private final class NotificationObservation: @unchecked Sendable {
    private let token: NSObjectProtocol

    init(name: Notification.Name, handler: @escaping @Sendable () -> Void) {
        token = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in handler() }
    }

    deinit {
        NotificationCenter.default.removeObserver(token)
    }
}

private final class MemoryWarningRelay: @unchecked Sendable {
    // Assigned before the observer can act and never mutated afterward.
    var handler: (@MainActor () -> Void)?

    func notify() {
        Task { @MainActor [handler] in handler?() }
    }
}

private enum AirCanvasPerformanceConfiguration {
    /// Avoids repeating an identical AR raycast when 2D smoothing has not
    /// produced a visually meaningful cursor change.
    static let cursorRaycastDisplayEpsilon: CGFloat = 0.5
}

/// Runtime-only hand interaction state for Select mode. It intentionally stores
/// the immutable pre-grab snapshot so preview transforms never accumulate drift.
enum HandSelectionState: Equatable {
    case idle
    case hovering(Stroke.ID)
    case grabbed(
        strokeID: Stroke.ID,
        initialHandPosition: SIMD3<Float>,
        originalStroke: Stroke,
        translation: SIMD3<Float>
    )
}

enum TouchStrokeMoveState: Equatable {
    case idle
    case dragging(strokeID: Stroke.ID, initialTouchPosition: SIMD3<Float>, originalStroke: Stroke, translation: SIMD3<Float>)
}

enum StrokeTransformState: Equatable {
    case idle
    case active(strokeID: Stroke.ID, original: Stroke, pivot: CanvasPoint3D, scale: Float, angle: Float)
}

enum EraseInteractionState: Equatable {
    case idle
    case hovering(Stroke.ID)
}

@MainActor
@Observable
final class CanvasARViewModel {
    private let sessionService: any ARSessionControlling
    private let raycastService: any SpatialRaycasting
    private let drawingEngine: DrawingEngine
    private let strokeRenderer: any StrokeRendering
    private let saveCoordinator: CanvasProjectSaveCoordinator
    private let repository: any CanvasProjectRepository
    private let handTrackingCoordinator: HandTrackingCoordinator?
    private let spatialCursorRenderer: (any SpatialCursorRendering)?
    private var spatialFingertipProcessor = SpatialFingertipProcessor()
    private var lastSpatialRaycastDisplayPoint: CGPoint?
    private var pinchClassifier = PinchGestureClassifier()
    /// Installed only by the onboarding runtime while gesture coaching is
    /// visible. The classifier remains the production classifier; this flag
    /// merely suppresses document-mutating tool routing for that short stage.
    private var isOnboardingPinchVerificationActive = false
    private var onboardingPinchEventHandler: ((PinchGestureEvent) -> Void)?
    private var onboardingCommittedStrokeHandler: ((Stroke.ID, UUID) -> Void)?
    private let spatialStrokeHitTester = SpatialStrokeHitTester()
    private let eraseStrokeHitTester = SpatialStrokeHitTester(configuration: .init(selectionRadius: 0.10))
    private let strokeTransformer = StrokeTransformer()
    private var history: CanvasHistory
    private var isCanvasVisible = false
    private var isApplicationActive = false
    private var autosaveTask: Task<Void, Never>?
    private var relocalizationTimeoutTask: Task<Void, Never>?
    nonisolated private let memoryWarningRelay: MemoryWarningRelay
    nonisolated private let memoryWarningObservation: NotificationObservation
    private(set) var currentDocumentRevision = 0
    private(set) var lastPersistedDocumentRevision = 0
    private var hasReconstructedProject = false
    private let requiresRelocalization: Bool
    private(set) var brushSettings: BrushSettings

    private(set) var activeProject: CanvasProject
    private(set) var sessionState: ARSessionState = .idle
    private(set) var placementHint: String?
    private(set) var canvasTool: CanvasTool = .draw
    private(set) var selectedStrokeID: Stroke.ID?
    private(set) var persistenceState: CanvasProjectPersistenceState = .clean
    private(set) var relocalizationState: SpatialRelocalizationState
    private(set) var mappingQuality: SpatialMappingQuality = .unavailable
    private(set) var handTrackingState: HandTrackingState = .noHand
    private(set) var pinchGestureState: PinchGestureState = .idle
    private(set) var spatialFingertipState: SpatialFingertipState = .unavailable
    private(set) var drawingInputSource: DrawingInputSource = .none
    private(set) var handSelectionState: HandSelectionState = .idle
    private(set) var touchStrokeMoveState: TouchStrokeMoveState = .idle
    private(set) var eraseInteractionState: EraseInteractionState = .idle
    private(set) var strokeTransformState: StrokeTransformState = .idle
    private(set) var transformScale: Float = 1
    private(set) var transformAngleDegrees: Float = 0

    var isDrawing: Bool {
        drawingEngine.isDrawing
    }

    var completedStrokes: [Stroke] {
        drawingEngine.completedStrokes
    }

    var canUndo: Bool {
        !drawingEngine.isDrawing && !isHandManipulating && !isTouchManipulating && history.canUndo
    }

    var canRedo: Bool {
        !drawingEngine.isDrawing && !isHandManipulating && !isTouchManipulating && history.canRedo
    }

    var canDeleteSelectedStroke: Bool {
        !drawingEngine.isDrawing && !isHandManipulating && !isTouchManipulating && !isTransforming && canvasTool == .select && selectedStrokeID != nil
    }

    var projectName: String {
        activeProject.name
    }

    var isProjectDirty: Bool {
        currentDocumentRevision > lastPersistedDocumentRevision
    }

    /// Captures the current authoritative document immediately, rather than
    /// waiting for the normal autosave debounce before an export is prepared.
    func projectSnapshotForExport() -> CanvasProject {
        flushProjectSave()
        return activeProject
    }

    private var isHandManipulating: Bool {
        if case .grabbed = handSelectionState { return true }
        return false
    }

    private var isTouchManipulating: Bool {
        if case .dragging = touchStrokeMoveState { return true }
        return false
    }

    var isTransforming: Bool {
        if case .active = strokeTransformState { return true }
        return false
    }

    init(
        sessionService: any ARSessionControlling,
        raycastService: any SpatialRaycasting,
        drawingEngine: DrawingEngine,
        strokeRenderer: any StrokeRendering,
        brushSettings: BrushSettings,
        project: CanvasProject,
        repository: any CanvasProjectRepository,
        handTrackingCoordinator: HandTrackingCoordinator? = nil,
        spatialCursorRenderer: (any SpatialCursorRendering)? = nil,
        relocalizationState: SpatialRelocalizationState = .none,
        history: CanvasHistory = CanvasHistory()
    ) {
        let memoryWarningRelay = MemoryWarningRelay()
        self.memoryWarningRelay = memoryWarningRelay
        self.memoryWarningObservation = NotificationObservation(
            name: UIApplication.didReceiveMemoryWarningNotification
        ) { memoryWarningRelay.notify() }
        self.sessionService = sessionService
        self.raycastService = raycastService
        self.drawingEngine = drawingEngine
        self.strokeRenderer = strokeRenderer
        self.brushSettings = brushSettings
        self.activeProject = project
        self.requiresRelocalization = project.spatialState != nil
        self.relocalizationState = relocalizationState
        self.saveCoordinator = CanvasProjectSaveCoordinator(repository: repository)
        self.repository = repository
        self.handTrackingCoordinator = handTrackingCoordinator
        self.spatialCursorRenderer = spatialCursorRenderer
        self.history = history
        precondition(
            drawingEngine.completedStrokes == project.strokes,
            "Canvas drawing state must match its active project at construction."
        )
        sessionService.setEventHandler { [weak self] event in
            self?.handle(event)
        }
        handTrackingCoordinator?.setStateHandler { [weak self] state in
            self?.consumeHandTrackingState(state)
        }
        memoryWarningRelay.handler = { [weak self] in
            self?.handleMemoryWarning()
        }
    }

    func canvasDidAppear(isApplicationActive: Bool) {
        isCanvasVisible = true
        self.isApplicationActive = isApplicationActive
        if relocalizationState == .none || relocalizationState == .fallback {
            reconstructPersistedStrokesIfNeeded()
        }
        updateSessionDemand()
    }

    private func handleMemoryWarning() {
        strokeRenderer.handleMemoryWarning()
        AppLogger.performance.notice("Canvas received a memory warning; authoritative document state was retained")
    }

    func canvasDidDisappear() {
        cancelStrokeTransform()
        clearEraseInteraction()
        cancelHandManipulation()
        cancelTouchStrokeManipulation()
        clearSpatialFingertip()
        resetPinchGesture()
        relocalizationTimeoutTask?.cancel()
        cancelActiveStroke()
        drawingInputSource = .none
        flushProjectSave()
        captureSpatialStateIfReady()
        clearSelection()
        strokeRenderer.clear()
        hasReconstructedProject = false
        isCanvasVisible = false
        updateSessionDemand()
    }

    func applicationActivityDidChange(isActive: Bool) {
        if !isActive {
            cancelStrokeTransform()
            clearEraseInteraction()
            cancelHandManipulation()
            clearSpatialFingertip()
            resetPinchGesture()
            cancelActiveStroke()
            drawingInputSource = .none
            flushProjectSave()
            captureSpatialStateIfReady()
        }
        isApplicationActive = isActive
        updateSessionDemand()
    }

    func retrySession() {
        guard isCanvasVisible && isApplicationActive else {
            return
        }

        sessionService.restart()
    }

    func setOnboardingPinchVerification(
        active: Bool,
        eventHandler: ((PinchGestureEvent) -> Void)? = nil
    ) {
        guard active != isOnboardingPinchVerificationActive else {
            onboardingPinchEventHandler = eventHandler
            return
        }
        isOnboardingPinchVerificationActive = active
        onboardingPinchEventHandler = active ? eventHandler : nil
        if active {
            // Entering a non-mutating coaching mode must not inherit an
            // unfinished editor interaction from a prior stage.
            cancelStrokeTransform()
            clearEraseInteraction()
            cancelHandManipulation()
            cancelActiveStroke()
            drawingInputSource = .none
        }
    }

    func setOnboardingCommittedStrokeObserver(_ observer: ((Stroke.ID, UUID) -> Void)?) {
        onboardingCommittedStrokeHandler = observer
    }

    func cancelOnboardingFirstStroke() {
        cancelActiveStroke()
        drawingInputSource = .none
    }

    func openWithoutSpatialAlignment() {
        guard requiresRelocalization else { return }
        cancelHandManipulation()
        cancelTouchStrokeManipulation()
        relocalizationState = .fallback
        relocalizationTimeoutTask?.cancel()
        reconstructPersistedStrokesIfNeeded()
        placementHint = "Original physical placement was not restored."
        AppLogger.ar.notice("User opened Canvas without spatial alignment")
    }

    func continueRelocalization() {
        guard requiresRelocalization, relocalizationState == .failed(.notFound) else { return }
        cancelHandManipulation()
        cancelTouchStrokeManipulation()
        relocalizationState = .scanning
        scheduleRelocalizationTimeout()
    }

    func retryProjectSave() {
        guard persistenceState == .failed else {
            return
        }
        scheduleProjectSave(after: .zero)
    }

    func selectBrushColor(_ color: BrushColor) {
        updateBrushSettings(color: color)
    }

    func updateBrushThickness(_ thickness: Float) {
        updateBrushSettings(thickness: CanvasBrushConfiguration.clampedThickness(thickness))
    }

    func selectTool(_ tool: CanvasTool) {
        guard canvasTool != tool else {
            return
        }

        cancelHandManipulation()
        cancelStrokeTransform()
        clearEraseInteraction()
        cancelActiveStroke()
        drawingInputSource = .none
        canvasTool = tool
        if tool != .select {
            clearSelection()
        }
    }

    func beginScaleTransform() {
        beginStrokeTransformIfNeeded()
    }

    func updateScaleTransform(_ scale: Float) {
        guard case let .active(strokeID, original, pivot, _, angle) = strokeTransformState,
              let clamped = strokeTransformer.configuration.clampedScale(scale),
              let preview = strokeTransformer.scale(original, by: clamped, around: pivot) else { return }
        transformScale = clamped
        strokeTransformState = .active(strokeID: strokeID, original: original, pivot: pivot, scale: clamped, angle: angle)
        _ = strokeRenderer.renderStroke(preview)
        _ = strokeRenderer.setSelectedStrokeID(strokeID)
    }

    func beginRotationTransform() {
        beginStrokeTransformIfNeeded()
    }

    func updateRotationTransform(_ degrees: Float) {
        guard case let .active(strokeID, original, pivot, scale, _) = strokeTransformState,
              degrees.isFinite,
              let preview = strokeTransformer.scale(original, by: scale, around: pivot).flatMap({ strokeTransformer.rotate($0, by: degrees * .pi / 180, around: pivot) }) else { return }
        transformAngleDegrees = degrees
        strokeTransformState = .active(strokeID: strokeID, original: original, pivot: pivot, scale: scale, angle: degrees)
        _ = strokeRenderer.renderStroke(preview)
        _ = strokeRenderer.setSelectedStrokeID(strokeID)
    }

    func endStrokeTransform() {
        guard case let .active(strokeID, original, pivot, scale, angle) = strokeTransformState,
              let scaled = strokeTransformer.scale(original, by: scale, around: pivot),
              let transformed = strokeTransformer.rotate(scaled, by: angle * .pi / 180, around: pivot) else {
            cancelStrokeTransform(); return
        }
        strokeTransformState = .idle
        transformScale = 1
        transformAngleDegrees = 0
        guard transformed != original else {
            _ = strokeRenderer.renderStroke(original)
            _ = strokeRenderer.setSelectedStrokeID(strokeID)
            return
        }
        guard drawingEngine.replaceCompletedStroke(transformed) != nil else {
            _ = strokeRenderer.renderStroke(original)
            _ = strokeRenderer.setSelectedStrokeID(strokeID)
            return
        }
        _ = strokeRenderer.renderStroke(transformed)
        _ = strokeRenderer.setSelectedStrokeID(strokeID)
        history.record(.moveStroke(before: original, after: transformed))
        documentDidChange()
    }

    func cancelStrokeTransform() {
        guard case let .active(strokeID, original, _, _, _) = strokeTransformState else { return }
        strokeTransformState = .idle
        transformScale = 1
        transformAngleDegrees = 0
        _ = strokeRenderer.renderStroke(original)
        _ = strokeRenderer.setSelectedStrokeID(strokeID)
    }

    private func beginStrokeTransformIfNeeded() {
        guard canvasTool == .select, !isHandManipulating, !drawingEngine.isDrawing,
              !isTransforming, let strokeID = selectedStrokeID,
              let original = drawingEngine.completedStrokes.first(where: { $0.id == strokeID }),
              let pivot = strokeTransformer.centroid(of: original) else { return }
        strokeTransformState = .active(strokeID: strokeID, original: original, pivot: pivot, scale: 1, angle: 0)
        transformScale = 1
        transformAngleDegrees = 0
    }

    func selectionDidRequest(at screenPoint: CGPoint) {
        guard canvasTool == .select, !isHandManipulating, !isTouchManipulating, !isTransforming else {
            return
        }
        guard isSpatialInteractionReady() else {
            return
        }

        guard let strokeID = strokeRenderer.strokeID(at: screenPoint) else {
            clearSelection()
            AppLogger.drawing.debug("Selection tap found no selectable stroke")
            return
        }
        guard drawingEngine.completedStrokes.contains(where: { $0.id == strokeID }) else {
            clearSelection()
            AppLogger.drawing.error("Renderer returned a stroke identifier absent from the Canvas document")
            return
        }
        guard strokeRenderer.setSelectedStrokeID(strokeID) else {
            clearSelection()
            renderingConsistencyFailure("A selected stroke could not receive selection feedback")
            return
        }

        _ = strokeRenderer.setHoveredStrokeID(nil)

        selectedStrokeID = strokeID
        placementHint = "Stroke selected. Delete is available."
        AppLogger.drawing.debug("Stroke selected")
    }

    func touchSelectionDragBegan(at screenPoint: CGPoint) {
        guard canvasTool == .select, !drawingEngine.isDrawing, !isHandManipulating, !isTouchManipulating, !isTransforming,
              let strokeID = selectedStrokeID,
              let original = drawingEngine.completedStrokes.first(where: { $0.id == strokeID }),
              let point = raycastWorldPoint(at: screenPoint) else { return }
        touchStrokeMoveState = .dragging(strokeID: strokeID, initialTouchPosition: point.simdValue, originalStroke: original, translation: .zero)
        placementHint = "Moving stroke. Lift your finger to place it."
    }

    func touchSelectionDragMoved(at screenPoint: CGPoint) {
        guard case let .dragging(strokeID, initial, original, _) = touchStrokeMoveState,
              let point = raycastWorldPoint(at: screenPoint) else { return }
        let translation = point.simdValue - initial
        guard translation.x.isFinite, translation.y.isFinite, translation.z.isFinite,
              original.translated(by: translation) != nil,
              strokeRenderer.setStrokeTranslation(translation, for: strokeID) else {
            cancelTouchStrokeManipulation()
            return
        }
        touchStrokeMoveState = .dragging(strokeID: strokeID, initialTouchPosition: initial, originalStroke: original, translation: translation)
    }

    func touchSelectionDragEnded(at screenPoint: CGPoint) {
        touchSelectionDragMoved(at: screenPoint)
        guard case let .dragging(strokeID, _, original, translation) = touchStrokeMoveState else { return }
        touchStrokeMoveState = .idle
        commitStrokeTranslation(strokeID: strokeID, originalStroke: original, translation: translation)
    }

    func touchSelectionDragCancelled() {
        cancelTouchStrokeManipulation()
    }

    private func cancelTouchStrokeManipulation() {
        guard case let .dragging(strokeID, _, _, _) = touchStrokeMoveState else { return }
        _ = strokeRenderer.setStrokeTranslation(.zero, for: strokeID)
        touchStrokeMoveState = .idle
        placementHint = nil
    }

    func deleteSelectedStroke() {
        guard !drawingEngine.isDrawing, !isHandManipulating, canvasTool == .select, let selectedStrokeID else {
            return
        }
        deleteStroke(id: selectedStrokeID)
    }

    func undoLastStroke() {
        guard !drawingEngine.isDrawing, !isHandManipulating else {
            return
        }
        guard let action = history.nextUndoAction else {
            return
        }

        guard reverse(action) else {
            return
        }

        _ = history.commitUndo()
        documentDidChange()
        switch action {
        case .addStroke:
            AppLogger.drawing.debug("Stroke addition undone")
        case .deleteStroke:
            AppLogger.drawing.debug("Stroke deletion undone")
        case .moveStroke:
            AppLogger.drawing.debug("Stroke move undone")
        }
    }

    func redoLastStroke() {
        guard !drawingEngine.isDrawing, !isHandManipulating else {
            return
        }
        guard let action = history.nextRedoAction else {
            return
        }

        guard apply(action) else {
            return
        }

        _ = history.commitRedo()
        documentDidChange()
        switch action {
        case .addStroke:
            AppLogger.drawing.debug("Stroke addition redone")
        case .deleteStroke:
            AppLogger.drawing.debug("Stroke deletion redone")
        case .moveStroke:
            AppLogger.drawing.debug("Stroke move redone")
        }
    }

    func touchDidBegin(at screenPoint: CGPoint, timestamp: TimeInterval) {
        guard drawingInputSource == .none, !isHandManipulating else { return }
        guard canvasTool == .draw else {
            return
        }
        guard let point = raycastWorldPoint(at: screenPoint) else {
            if placementHint == nil {
                placementHint = "No surface found. Move slowly and point toward a visible surface."
            }
            AppLogger.drawing.debug("Stroke start skipped because the initial raycast found no surface")
            return
        }

        switch drawingEngine.beginStroke(
            at: point,
            style: brushSettings.style,
            timestamp: timestamp
        ) {
        case .started(let id, let firstPoint, let style):
            drawingInputSource = .touch
            strokeRenderer.beginActiveStroke(id: id, style: style, firstPoint: firstPoint)
            placementHint = nil
            AppLogger.drawing.debug("Stroke began")
        case .alreadyDrawing:
            AppLogger.drawing.error("Stroke start requested while another stroke was active")
        case .rejectedInvalidTimestamp:
            placementHint = "Drawing input could not be used. Please try again."
            AppLogger.drawing.error("Stroke start rejected because the input timestamp was invalid")
        }
    }

    func touchDidMove(at screenPoint: CGPoint, timestamp: TimeInterval) {
        guard drawingInputSource == .touch else { return }
        guard canvasTool == .draw else {
            return
        }
        guard drawingEngine.isDrawing else {
            return
        }

        guard let point = raycastWorldPoint(at: screenPoint) else {
            return
        }

        switch drawingEngine.appendPoint(at: point, timestamp: timestamp) {
        case .appended(let id, let previousPoint, let strokePoint, let style):
            strokeRenderer.appendActiveStrokePoint(
                strokeID: id,
                from: previousPoint,
                to: strokePoint,
                style: style
            )
        case .ignoredTooClose, .noActiveStroke:
            break
        case .ignoredAtCapacity:
            placementHint = "Stroke length limit reached. Lift your finger to finish it."
        case .rejectedInvalidTimestamp:
            cancelActiveStroke()
            placementHint = "Drawing input was interrupted. Please try again."
            AppLogger.drawing.error("Active stroke cancelled because the input timestamp was invalid")
        }
    }

    func touchDidEnd(at screenPoint: CGPoint, timestamp: TimeInterval) {
        guard drawingInputSource == .touch else { return }
        guard canvasTool == .draw else {
            return
        }
        touchDidMove(at: screenPoint, timestamp: timestamp)

        switch drawingEngine.endStroke() {
        case .completed(let stroke):
            history.record(.addStroke(stroke))
            if strokeRenderer.finalizeStroke(stroke) {
                placementHint = nil
            } else {
                renderingConsistencyFailure("Completed stroke was saved in the Canvas document, but rendering failed")
            }
            documentDidChange()
            AppLogger.drawing.debug("Stroke completed")
        case .discarded(let id):
            strokeRenderer.removeStroke(id: id)
            AppLogger.drawing.debug("Stroke discarded because it did not meet the minimum point count")
        case .noActiveStroke:
            break
        }
        drawingInputSource = .none
    }

    func touchDidCancel() {
        cancelActiveStroke()
        drawingInputSource = .none
    }

    private func updateSessionDemand() {
        if isCanvasVisible && isApplicationActive {
            sessionService.start()
            handTrackingCoordinator?.setEnabled(true)
        } else {
            handTrackingCoordinator?.setEnabled(false)
            handTrackingState = .noHand
            resetPinchGesture()
            sessionService.pause()
        }
    }

    private func consumeHandTrackingState(_ state: HandTrackingState) {
        handTrackingDidUpdate(state, timestamp: ProcessInfo.processInfo.systemUptime)
    }

    /// Receives an already-validated hand result from the Vision pipeline. Keeping
    /// the timestamp explicit makes the gesture-to-input boundary deterministic in
    /// tests without coupling the classifier to ARKit or SwiftUI.
    func handTrackingDidUpdate(_ state: HandTrackingState, timestamp: TimeInterval) {
        handTrackingState = state
        let event = pinchClassifier.update(hand: state, timestamp: timestamp)
        pinchGestureState = pinchClassifier.state
        if isOnboardingPinchVerificationActive {
            if let event { onboardingPinchEventHandler?(event) }
            return
        }
        switch event {
        case .began:
            if canvasTool == .draw {
                beginHandStroke()
            } else if canvasTool == .select {
                beginHandManipulation()
            } else {
                eraseHoveredStroke()
            }
        case .ended:
            if canvasTool == .draw {
                endHandStroke()
            } else if canvasTool == .select {
                commitHandManipulation()
            }
        case .cancelled:
            cancelHandStroke()
            cancelHandManipulation()
            clearEraseInteraction()
        case nil: break
        }
    }

    private func resetPinchGesture() {
        cancelHandStroke()
        cancelHandManipulation()
        pinchClassifier.reset()
        pinchGestureState = .idle
    }

    private func beginHandStroke() {
        guard canvasTool == .draw, handSelectionState == .idle, drawingInputSource == .none, case .tracked(let world) = spatialFingertipState, let point = try? CanvasPoint3D(simdValue: world) else { return }
        switch drawingEngine.beginStroke(at: point, style: brushSettings.style, timestamp: ProcessInfo.processInfo.systemUptime) {
        case .started(let id, let first, let style): drawingInputSource = .hand; strokeRenderer.beginActiveStroke(id: id, style: style, firstPoint: first)
        default: break
        }
    }
    private func appendHandStroke() {
        guard drawingInputSource == .hand, pinchGestureState == .pinching, case .tracked(let world) = spatialFingertipState, let point = try? CanvasPoint3D(simdValue: world) else { return }
        if case .appended(let id, let prior, let next, let style) = drawingEngine.appendPoint(at: point, timestamp: ProcessInfo.processInfo.systemUptime) { strokeRenderer.appendActiveStrokePoint(strokeID: id, from: prior, to: next, style: style) }
    }
    private func endHandStroke() {
        guard drawingInputSource == .hand else { return }
        if case .completed(let stroke) = drawingEngine.endStroke() {
            history.record(.addStroke(stroke)); _ = strokeRenderer.finalizeStroke(stroke); documentDidChange()
            onboardingCommittedStrokeHandler?(stroke.id, activeProject.id)
        }
        drawingInputSource = .none
    }
    private func cancelHandStroke() { guard drawingInputSource == .hand else { return }; cancelActiveStroke(); drawingInputSource = .none }

    private func updateHandSelection(with handWorldPosition: SIMD3<Float>) {
        guard canvasTool == .select else { return }

        switch handSelectionState {
        case .grabbed:
            updateHandManipulation(to: handWorldPosition)
        case .idle, .hovering:
            let candidate = spatialStrokeHitTester.nearestStrokeID(
                to: handWorldPosition,
                in: drawingEngine.completedStrokes
            )
            updateHandHover(candidate)
        }
    }

    private func updateEraseCandidate(with handWorldPosition: SIMD3<Float>) {
        guard canvasTool == .erase, drawingInputSource == .none, !isHandManipulating, !isTransforming else { return }
        let candidate = eraseStrokeHitTester.nearestStrokeID(to: handWorldPosition, in: drawingEngine.completedStrokes)
        let current: Stroke.ID? = if case .hovering(let id) = eraseInteractionState { id } else { nil }
        guard candidate != current else { return }
        _ = strokeRenderer.setHoveredStrokeID(candidate)
        eraseInteractionState = candidate.map(EraseInteractionState.hovering) ?? .idle
        placementHint = candidate == nil ? nil : "Pinch to erase stroke."
    }

    private func eraseHoveredStroke() {
        guard canvasTool == .erase, drawingInputSource == .none, !isHandManipulating, !isTransforming,
              case .hovering(let strokeID) = eraseInteractionState else { return }
        clearEraseInteraction()
        deleteStroke(id: strokeID)
    }

    private func clearEraseInteraction() {
        guard eraseInteractionState != .idle else { return }
        _ = strokeRenderer.setHoveredStrokeID(nil)
        eraseInteractionState = .idle
        if placementHint == "Pinch to erase stroke." { placementHint = nil }
    }

    private func deleteStroke(id: Stroke.ID) {
        guard let removal = drawingEngine.removeCompletedStroke(id: id) else {
            if selectedStrokeID == id { clearSelection() }
            return
        }
        if selectedStrokeID == id { clearSelection() }
        clearEraseInteraction()
        if !strokeRenderer.removeStroke(id: removal.stroke.id) {
            renderingConsistencyFailure("Delete removed a stroke from the document, but no rendered stroke was found")
        }
        history.record(.deleteStroke(removal.stroke, originalIndex: removal.index))
        documentDidChange()
        placementHint = nil
        AppLogger.drawing.debug("Stroke deleted")
    }

    private func updateHandHover(_ candidate: Stroke.ID?) {
        let currentCandidate: Stroke.ID?
        if case .hovering(let strokeID) = handSelectionState {
            currentCandidate = strokeID
        } else {
            currentCandidate = nil
        }
        guard candidate != currentCandidate else { return }

        guard let candidate else {
            clearHandSelection()
            return
        }
        guard strokeRenderer.setHoveredStrokeID(candidate) else {
            handSelectionState = .idle
            renderingConsistencyFailure("A hovered stroke could not receive hand-selection feedback")
            return
        }

        handSelectionState = .hovering(candidate)
        placementHint = "Pinch to move stroke."
        AppLogger.drawing.debug("Hand hover acquired")
    }

    private func clearHandSelection() {
        _ = strokeRenderer.setHoveredStrokeID(nil)
        handSelectionState = .idle
        if placementHint == "Pinch to move stroke." {
            placementHint = nil
        }
    }

    private func beginHandManipulation() {
        guard canvasTool == .select,
              drawingInputSource == .none,
              !drawingEngine.isDrawing,
              !isTransforming,
              case .hovering(let strokeID) = handSelectionState,
              case .tracked(let handWorldPosition) = spatialFingertipState,
              let originalStroke = drawingEngine.completedStrokes.first(where: { $0.id == strokeID }) else {
            return
        }

        handSelectionState = .grabbed(
            strokeID: strokeID,
            initialHandPosition: handWorldPosition,
            originalStroke: originalStroke,
            translation: .zero
        )
        placementHint = "Moving stroke. Release to place."
        AppLogger.drawing.debug("Hand stroke grab began")
    }

    private func updateHandManipulation(to handWorldPosition: SIMD3<Float>) {
        guard case let .grabbed(strokeID, initialHandPosition, originalStroke, _) = handSelectionState else {
            return
        }
        let translation = handWorldPosition - initialHandPosition
        guard translation.x.isFinite, translation.y.isFinite, translation.z.isFinite,
              originalStroke.translated(by: translation) != nil else {
            cancelHandManipulation()
            return
        }
        guard strokeRenderer.setStrokeTranslation(translation, for: strokeID) else {
            cancelHandManipulation()
            renderingConsistencyFailure("A grabbed stroke could not update its preview")
            return
        }
        handSelectionState = .grabbed(
            strokeID: strokeID,
            initialHandPosition: initialHandPosition,
            originalStroke: originalStroke,
            translation: translation
        )
    }

    private func commitHandManipulation() {
        guard case let .grabbed(strokeID, _, originalStroke, translation) = handSelectionState else {
            return
        }
        defer { handSelectionState = .idle }

        guard let movedStroke = originalStroke.translated(by: translation) else {
            cancelHandManipulation()
            return
        }
        guard movedStroke != originalStroke else {
            _ = strokeRenderer.setStrokeTranslation(.zero, for: strokeID)
            _ = strokeRenderer.setHoveredStrokeID(nil)
            _ = strokeRenderer.setSelectedStrokeID(strokeID)
            selectedStrokeID = strokeID
            placementHint = "Stroke selected. Delete is available."
            return
        }
        guard drawingEngine.replaceCompletedStroke(movedStroke) != nil else {
            _ = strokeRenderer.setStrokeTranslation(.zero, for: strokeID)
            historyConsistencyFailure("Hand move could not find its stroke in the Canvas document")
            return
        }
        guard strokeRenderer.renderStroke(movedStroke) else {
            _ = drawingEngine.replaceCompletedStroke(originalStroke)
            _ = strokeRenderer.renderStroke(originalStroke)
            renderingConsistencyFailure("Hand move could not update the stroke renderer")
            return
        }

        _ = strokeRenderer.setSelectedStrokeID(strokeID)
        _ = strokeRenderer.setHoveredStrokeID(nil)
        selectedStrokeID = strokeID
        history.record(.moveStroke(before: originalStroke, after: movedStroke))
        documentDidChange()
        placementHint = "Stroke moved."
        AppLogger.drawing.debug("Hand stroke move committed")
    }

    private func cancelHandManipulation() {
        guard case let .grabbed(strokeID, _, _, _) = handSelectionState else { return }
        _ = strokeRenderer.setStrokeTranslation(.zero, for: strokeID)
        handSelectionState = .idle
        placementHint = nil
        AppLogger.drawing.debug("Hand stroke move cancelled")
    }

    /// Shared snapshot-based commit path for hand and touch translation. Every
    /// preview is derived from the original stroke; only this semantic end step
    /// mutates the document and records one history action.
    private func commitStrokeTranslation(strokeID: Stroke.ID, originalStroke: Stroke, translation: SIMD3<Float>) {
        guard let movedStroke = originalStroke.translated(by: translation) else {
            _ = strokeRenderer.setStrokeTranslation(.zero, for: strokeID)
            return
        }
        guard movedStroke != originalStroke else {
            _ = strokeRenderer.setStrokeTranslation(.zero, for: strokeID)
            _ = strokeRenderer.setSelectedStrokeID(strokeID)
            selectedStrokeID = strokeID
            placementHint = "Stroke selected. Delete is available."
            return
        }
        guard drawingEngine.replaceCompletedStroke(movedStroke) != nil else {
            _ = strokeRenderer.setStrokeTranslation(.zero, for: strokeID)
            historyConsistencyFailure("Touch move could not find its stroke in the Canvas document")
            return
        }
        guard strokeRenderer.renderStroke(movedStroke) else {
            _ = drawingEngine.replaceCompletedStroke(originalStroke)
            _ = strokeRenderer.renderStroke(originalStroke)
            renderingConsistencyFailure("A stroke move could not update the renderer")
            return
        }
        _ = strokeRenderer.setSelectedStrokeID(strokeID)
        _ = strokeRenderer.setHoveredStrokeID(nil)
        selectedStrokeID = strokeID
        history.record(.moveStroke(before: originalStroke, after: movedStroke))
        documentDidChange()
        placementHint = "Stroke moved."
    }

    func updateSpatialFingertip(_ state: FingertipTrackingState) {
        guard isSpatialInteractionReady(), case .tracking(let displayPoint) = state else { clearSpatialFingertip(); return }
        if let previous = lastSpatialRaycastDisplayPoint,
           hypot(displayPoint.x - previous.x, displayPoint.y - previous.y) < AirCanvasPerformanceConfiguration.cursorRaycastDisplayEpsilon {
            return
        }
        lastSpatialRaycastDisplayPoint = displayPoint
        guard let result = raycastService.raycast(at: displayPoint), result.worldPosition.x.isFinite, result.worldPosition.y.isFinite, result.worldPosition.z.isFinite else { spatialFingertipState = .searching; spatialCursorRenderer?.updateSpatialCursor(position: nil, isPinching: pinchGestureState == .pinching); return }
        guard let worldPoint = spatialFingertipProcessor.accept(result.worldPosition) else { return }
        spatialFingertipState = .tracked(worldPoint)
        spatialCursorRenderer?.updateSpatialCursor(position: worldPoint, isPinching: pinchGestureState == .pinching)
        appendHandStroke()
        updateHandSelection(with: worldPoint)
        updateEraseCandidate(with: worldPoint)
    }
    private func clearSpatialFingertip() {
        spatialFingertipProcessor.reset()
        lastSpatialRaycastDisplayPoint = nil
        spatialFingertipState = .unavailable
        if case .hovering = handSelectionState {
            clearHandSelection()
        }
        clearEraseInteraction()
        spatialCursorRenderer?.updateSpatialCursor(position: nil, isPinching: false)
    }

    private func updateBrushSettings(color: BrushColor? = nil, thickness: Float? = nil) {
        do {
            try brushSettings.update(color: color, thickness: thickness)
        } catch {
            placementHint = "Brush settings could not be applied. Please try again."
            AppLogger.drawing.error("Brush settings update failed: \(error.localizedDescription, privacy: .private(mask: .hash))")
        }
    }

    private func handle(_ event: ARSessionEvent) {
        sessionState = ARSessionStateReducer.state(after: event, from: sessionState)

        switch event {
        case .mappingQualityChanged(let quality):
            mappingQuality = quality
        case .trackingChanged(.normal):
            if requiresRelocalization,
               relocalizationState == .scanning || relocalizationState == .preparing {
                relocalizationState = .localized
                relocalizationTimeoutTask?.cancel()
                reconstructPersistedStrokesIfNeeded()
                AppLogger.ar.info("AR world-map relocalization succeeded")
            }
            placementHint = nil
        case .trackingChanged, .interrupted, .failed, .paused:
            resetPinchGesture()
            cancelActiveStroke()
            clearSpatialFingertip()
        case .started:
            if requiresRelocalization, relocalizationState == .preparing {
                relocalizationState = .scanning
                scheduleRelocalizationTimeout()
            }
        case .interruptionEnded:
            break
        }
    }

    private func raycastWorldPoint(at screenPoint: CGPoint) -> CanvasPoint3D? {
        guard isSpatialInteractionReady() else {
            return nil
        }

        guard let result = raycastService.raycast(at: screenPoint) else {
            return nil
        }

        guard let point = try? CanvasPoint3D(simdValue: result.worldPosition) else {
            AppLogger.drawing.error("Spatial raycast returned an invalid world position")
            return nil
        }
        return point
    }

    private func cancelActiveStroke() {
        defer { drawingInputSource = .none }
        guard let id = drawingEngine.cancelStroke() else { return }

        strokeRenderer.removeStroke(id: id)
        AppLogger.drawing.debug("Active stroke cancelled")
    }

    private func reconstructPersistedStrokesIfNeeded() {
        guard !hasReconstructedProject else {
            return
        }
        hasReconstructedProject = true

        for stroke in activeProject.strokes {
            guard strokeRenderer.renderStroke(stroke) else {
                renderingConsistencyFailure("A persisted stroke could not be reconstructed for this Canvas session")
                return
            }
        }

        if !activeProject.strokes.isEmpty {
            placementHint = "Saved strokes were reconstructed. Exact room alignment is not restored yet."
        }
    }

    private func documentDidChange() {
        do {
            activeProject = try activeProject.replacingStrokes(drawingEngine.completedStrokes)
        } catch {
            persistenceFailure("The active canvas could not be updated. Your current drawing remains available. Please try again.")
            AppLogger.persistence.error("Active Canvas project update failed: \(error.localizedDescription, privacy: .private(mask: .hash))")
            return
        }

        currentDocumentRevision += 1
        persistenceState = .dirty
        scheduleProjectSave(after: .milliseconds(750))
    }

    private func scheduleProjectSave(after delay: Duration) {
        autosaveTask?.cancel()
        let project = activeProject
        let revision = currentDocumentRevision
        autosaveTask = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard !Task.isCancelled else {
                return
            }
            await self?.save(project, revision: revision)
        }
    }

    private func flushProjectSave() {
        autosaveTask?.cancel()
        let project = activeProject
        let revision = currentDocumentRevision
        Task { [weak self] in
            await self?.save(project, revision: revision)
        }
    }

    private func captureSpatialStateIfReady() {
        guard mappingQuality.isSufficientForSpatialRestore,
              isCanvasVisible,
              relocalizationState != .fallback else {
            return
        }
        let project = activeProject
        Task { [weak self] in
            guard let self else { return }
            do {
                AppLogger.ar.debug("Requesting AR world map for spatial save")
                let worldMap = try await sessionService.requestWorldMap()
                let archive = try SpatialWorldMapCoder.archive(worldMap)
                let state = try SpatialCanvasState(mappingQuality: mappingQuality)
                let updated = try await repository.replaceSpatialState(
                    for: project,
                    archivedWorldMap: archive,
                    state: state
                )
                guard activeProject.id == updated.id else { return }
                activeProject = updated
                AppLogger.ar.info("Saved AR world map for Canvas project")
            } catch {
                AppLogger.ar.error("Unable to save AR world map: \(error.localizedDescription, privacy: .private(mask: .hash))")
            }
        }
    }

    private func scheduleRelocalizationTimeout() {
        relocalizationTimeoutTask?.cancel()
        relocalizationTimeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(45))
            } catch {
                return
            }
            guard !Task.isCancelled,
                  self?.relocalizationState == .scanning else { return }
            self?.relocalizationState = .failed(.notFound)
            AppLogger.ar.notice("AR world-map relocalization is still incomplete after guidance interval")
        }
    }

    private func save(_ project: CanvasProject, revision: Int) async {
        if revision == currentDocumentRevision {
            persistenceState = .saving
        }

        do {
            let disposition = try await saveCoordinator.save(project, revision: revision)
            guard disposition == .persisted else {
                return
            }
            lastPersistedDocumentRevision = max(lastPersistedDocumentRevision, revision)
            if revision == currentDocumentRevision {
                persistenceState = .clean
            }
        } catch {
            guard revision == currentDocumentRevision else {
                return
            }
            persistenceFailure("Changes could not be saved. Your current drawing remains available. Try saving again before leaving.")
            AppLogger.persistence.error("Canvas project autosave failed: \(error.localizedDescription, privacy: .private(mask: .hash))")
        }
    }

    private func persistenceFailure(_ message: String) {
        persistenceState = .failed
        placementHint = message
    }

    private func reverse(_ action: CanvasAction) -> Bool {
        switch action {
        case .addStroke(let stroke):
            return remove(stroke, operation: "Undo")
        case .deleteStroke(let stroke, let originalIndex):
            return restore(stroke, at: originalIndex, operation: "Undo")
        case .moveStroke(let before, _):
            return replace(before, operation: "Undo")
        }
    }

    private func apply(_ action: CanvasAction) -> Bool {
        switch action {
        case .addStroke(let stroke):
            return restore(stroke, at: drawingEngine.completedStrokes.endIndex, operation: "Redo")
        case .deleteStroke(let stroke, _):
            return remove(stroke, operation: "Redo")
        case .moveStroke(_, let after):
            return replace(after, operation: "Redo")
        }
    }

    private func remove(_ stroke: Stroke, operation: String) -> Bool {
        guard drawingEngine.removeCompletedStroke(id: stroke.id) != nil else {
            historyConsistencyFailure("\(operation) could not find its stroke in the Canvas document")
            return false
        }
        if selectedStrokeID == stroke.id {
            clearSelection()
        }
        if !strokeRenderer.removeStroke(id: stroke.id) {
            renderingConsistencyFailure("\(operation) removed a stroke from the document, but no rendered stroke was found")
        }
        return true
    }

    private func restore(_ stroke: Stroke, at index: Int, operation: String) -> Bool {
        guard drawingEngine.restoreCompletedStroke(stroke, at: index) else {
            historyConsistencyFailure("\(operation) could not restore its stroke into the Canvas document")
            return false
        }
        if !strokeRenderer.renderStroke(stroke) {
            renderingConsistencyFailure("\(operation) restored a stroke in the document, but rendering failed")
        }
        return true
    }

    private func replace(_ stroke: Stroke, operation: String) -> Bool {
        guard drawingEngine.replaceCompletedStroke(stroke) != nil else {
            historyConsistencyFailure("\(operation) could not replace its stroke in the Canvas document")
            return false
        }
        guard strokeRenderer.renderStroke(stroke) else {
            renderingConsistencyFailure("\(operation) replaced a stroke in the document, but rendering failed")
            return false
        }
        if selectedStrokeID == stroke.id {
            _ = strokeRenderer.setSelectedStrokeID(stroke.id)
        }
        return true
    }

    private func clearSelection() {
        guard selectedStrokeID != nil else {
            return
        }
        _ = strokeRenderer.setSelectedStrokeID(nil)
        selectedStrokeID = nil
        if placementHint == "Stroke selected. Delete is available." {
            placementHint = nil
        }
        AppLogger.drawing.debug("Stroke selection cleared")
    }

    private func isSpatialInteractionReady() -> Bool {
        if requiresRelocalization,
           relocalizationState != .localized,
           relocalizationState != .fallback {
            placementHint = relocalizationState.guidance ?? "Spatial restoration is not ready for editing."
            cancelHandManipulation()
            cancelActiveStroke()
            return false
        }

        guard case .running(let trackingState) = sessionState else {
            placementHint = "Spatial tracking is not ready for this action."
            cancelHandManipulation()
            cancelActiveStroke()
            return false
        }

        switch SpatialRaycastReadiness(trackingState: trackingState) {
        case .ready:
            return true
        case .unavailable(let guidance):
            placementHint = guidance
            cancelHandManipulation()
            if drawingEngine.isDrawing {
                cancelActiveStroke()
            }
            drawingInputSource = .none
            return false
        }
    }

    private func historyConsistencyFailure(_ message: String) {
        placementHint = "Stroke history could not be applied. Please return Home and start a new canvas."
        AppLogger.drawing.error("\(message, privacy: .public)")
    }

    private func renderingConsistencyFailure(_ message: String) {
        placementHint = "A stroke display issue occurred. Your Canvas data is still available in this session."
        AppLogger.drawing.error("\(message, privacy: .public)")
    }
}

extension CanvasARViewModel: CanvasTouchInputHandling {}
