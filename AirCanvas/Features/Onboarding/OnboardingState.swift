import Foundation
import Observation

enum OnboardingStep: Equatable {
    case welcome, interactionBasics, cameraEducation
    case spatialPreparation, handCheck
    // These stages are deliberately reserved for the following focused substeps.
    // They must not be entered by the AR/hand bridge alone.
    case pinchCheck, firstStroke
    case cameraDenied, cameraRestricted, unsupportedDevice, complete
}

/// User-facing AR readiness derived from the one production `CanvasARViewModel`.
/// Keeping this ARKit-free lets onboarding UI and tests reason about readiness
/// without owning a second AR session.
enum SpatialReadinessState: Equatable {
    case preparing
    case ready
    case limited(SpatialTrackingLimitation)
    case interrupted
    case failed(String)
}

enum SpatialTrackingLimitation: Equatable {
    case initializing
    case excessiveMotion
    case insufficientFeatures
    case relocalizing
    case unavailable

    var guidance: String {
        switch self {
        case .initializing: "Preparing your space… Move your iPhone slowly to map your space."
        case .excessiveMotion: "Move your iPhone more slowly."
        case .insufficientFeatures: "Point your iPhone toward a well-lit area with visible surfaces."
        case .relocalizing: "Restoring your space…"
        case .unavailable: "Spatial tracking is temporarily unavailable."
        }
    }
}

/// Transient coaching state driven only by semantic events emitted from the
/// production pinch classifier. It intentionally contains no geometry or
/// threshold logic.
enum PinchVerificationState: Equatable {
    case waitingForPinch
    case waitingForRelease
    case completed
}

extension SpatialReadinessState {
    init(sessionState: ARSessionState) {
        switch sessionState {
        case .idle: self = .preparing
        case .interrupted: self = .interrupted
        case .failed(let failure): self = .failed(failure.message)
        case .running(.normal): self = .ready
        case .running(.initializing): self = .limited(.initializing)
        case .running(.unavailable): self = .limited(.unavailable)
        case .running(.limited(let limitation)):
            switch limitation {
            case .initializing: self = .limited(.initializing)
            case .excessiveMotion: self = .limited(.excessiveMotion)
            case .insufficientFeatures: self = .limited(.insufficientFeatures)
            case .relocalizing: self = .limited(.relocalizing)
            }
        }
    }
}

@MainActor
@Observable
final class OnboardingState {
    nonisolated static let completionKey = "AirCanvasOnboardingCompleted"
    nonisolated static let completionVersionKey = "AirCanvasOnboardingCompletionVersion"
    nonisolated static let onboardingCanvasIdentifierKey = "AirCanvasOnboardingCanvasIdentifier"
    nonisolated static let currentVersion = 2

    private let defaults: UserDefaults
    private let permissionProvider: any CameraPermissionProviding
    private let capabilityChecker: any SpatialCanvasCapabilityChecking
    private(set) var requiresOnboarding: Bool
    private(set) var step: OnboardingStep = .welcome
    private(set) var isRequestingCamera = false
    private(set) var spatialReadiness: SpatialReadinessState = .preparing
    private(set) var isHandReady = false
    private(set) var pinchVerificationState: PinchVerificationState = .waitingForPinch

    init(defaults: UserDefaults = .standard, permissionProvider: any CameraPermissionProviding = CameraPermissionService(), capabilityChecker: any SpatialCanvasCapabilityChecking = SpatialCanvasCapabilityService()) {
        self.defaults = defaults
        self.permissionProvider = permissionProvider
        self.capabilityChecker = capabilityChecker
        requiresOnboarding = !(defaults.bool(forKey: Self.completionKey) || defaults.integer(forKey: Self.completionVersionKey) >= Self.currentVersion)
    }

    func advance() async {
        switch step {
        case .welcome: step = .interactionBasics
        case .interactionBasics: step = .cameraEducation
        case .cameraEducation: await requestCameraAfterCapabilityCheck()
        default: break
        }
    }

    func goBack() {
        if step == .interactionBasics { step = .welcome }
        if step == .cameraEducation { step = .interactionBasics }
    }

    func requestCameraAfterCapabilityCheck() async {
        guard capabilityChecker.spatialCanvasCapability() == .supported else { step = .unsupportedDevice; return }
        isRequestingCamera = true
        let authorization = await permissionProvider.requestAccess()
        isRequestingCamera = false
        apply(authorization)
    }

    func refreshPermission() {
        guard capabilityChecker.spatialCanvasCapability() == .supported else { step = .unsupportedDevice; return }
        apply(permissionProvider.authorizationStatus())
    }

    var usesProductionSpatialRuntime: Bool {
        step == .spatialPreparation || step == .handCheck || step == .pinchCheck || step == .firstStroke
    }

    /// Receives observable state from the *existing* production canvas runtime.
    /// This is intentionally a narrow, domain-facing bridge: onboarding neither
    /// creates nor controls an AR session, Vision loop, raycaster, or cursor.
    func observeProductionRuntime(
        sessionState: ARSessionState,
        handState: HandTrackingState,
        fingertipState: SpatialFingertipState
    ) {
        guard usesProductionSpatialRuntime else { return }
        let readiness = SpatialReadinessState(sessionState: sessionState)
        spatialReadiness = readiness

        guard readiness == .ready else {
            isHandReady = false
            resetPinchVerification()
            return
        }

        if step == .spatialPreparation {
            step = .handCheck
        }

        // A real cursor requires both production hand validation and a
        // production-accepted world point. A Vision observation on its own is
        // not sufficient for onboarding success.
        isHandReady = {
            guard case .detected = handState,
                  case .tracked = fingertipState else { return false }
            return true
        }()

        if step == .pinchCheck, !isHandReady {
            resetPinchVerification()
        }
    }

    func continueFromHandCheck() {
        guard step == .handCheck, spatialReadiness == .ready, isHandReady else { return }
        resetPinchVerification()
        step = .pinchCheck
    }

    /// Consumes the exact `PinchGestureEvent` emitted by the already-running
    /// production classifier. No classifier configuration lives in onboarding.
    func observeProductionPinchEvent(_ event: PinchGestureEvent) {
        guard step == .pinchCheck, spatialReadiness == .ready, isHandReady else {
            resetPinchVerification()
            return
        }
        switch (pinchVerificationState, event) {
        case (.waitingForPinch, .began):
            pinchVerificationState = .waitingForRelease
        case (.waitingForRelease, .ended):
            pinchVerificationState = .completed
            step = .firstStroke
        case (.waitingForRelease, .cancelled):
            resetPinchVerification()
        case (.waitingForPinch, .ended), (.waitingForPinch, .cancelled), (.completed, _):
            break
        case (.waitingForRelease, .began):
            break
        }
    }

    func retryPinchVerification() {
        guard step == .pinchCheck else { return }
        resetPinchVerification()
    }

    func skipPinchVerification() {
        guard step == .pinchCheck else { return }
        resetPinchVerification()
        step = .firstStroke
    }

    /// A production document commit, not a preview or gesture transition,
    /// is the only event that completes first-stroke coaching.
    func observeCommittedOnboardingStroke(in canvasID: UUID) {
        guard step == .firstStroke, onboardingCanvasID == canvasID else { return }
        completeOnboarding()
    }

    func skipFirstStroke() {
        guard step == .firstStroke else { return }
        completeOnboarding()
    }

    func retrySpatialPreparation() {
        guard usesProductionSpatialRuntime else { return }
        spatialReadiness = .preparing
        isHandReady = false
        step = .spatialPreparation
    }

    private func resetPinchVerification() {
        pinchVerificationState = .waitingForPinch
    }

    func completeOnboarding() {
        defaults.set(true, forKey: Self.completionKey)
        defaults.set(Self.currentVersion, forKey: Self.completionVersionKey)
        requiresOnboarding = false
        step = .complete
        AppLogger.application.info("Onboarding completed")
    }

    func beginReplay() { requiresOnboarding = true; step = .welcome }

    var onboardingCanvasID: UUID? {
        defaults.string(forKey: Self.onboardingCanvasIdentifierKey).flatMap(UUID.init(uuidString:))
    }

    func rememberOnboardingCanvas(id: UUID) {
        defaults.set(id.uuidString, forKey: Self.onboardingCanvasIdentifierKey)
    }

    private func apply(_ authorization: CameraAuthorization) {
        resetPinchVerification()
        switch authorization {
        case .authorized:
            spatialReadiness = .preparing
            isHandReady = false
            step = .spatialPreparation
        case .denied: step = .cameraDenied
        case .restricted: step = .cameraRestricted
        case .notDetermined: step = .cameraEducation
        }
    }
}

extension UserDefaults {
    static var previewCompletedOnboarding: UserDefaults {
        let defaults = UserDefaults(suiteName: "AirCanvas.Preview.Onboarding") ?? .standard
        defaults.set(OnboardingState.currentVersion, forKey: OnboardingState.completionVersionKey)
        return defaults
    }
}
