import Observation

enum SpatialCanvasAccessState: Equatable {
    case checking
    case readyForCanvas
    case cameraAccessRequired
    case cameraAccessRestricted
    case unsupportedDevice
}

@MainActor
@Observable
final class SpatialCanvasAccessViewModel {
    private let cameraPermissionService: any CameraPermissionProviding
    private let capabilityService: any SpatialCanvasCapabilityChecking
    private var isEvaluating = false

    private(set) var state: SpatialCanvasAccessState = .checking

    init(
        cameraPermissionService: any CameraPermissionProviding = CameraPermissionService(),
        capabilityService: any SpatialCanvasCapabilityChecking = SpatialCanvasCapabilityService()
    ) {
        self.cameraPermissionService = cameraPermissionService
        self.capabilityService = capabilityService
    }

    func prepareForCanvas() async {
        guard !isEvaluating else {
            return
        }

        isEvaluating = true
        defer { isEvaluating = false }

        guard capabilityService.spatialCanvasCapability() == .supported else {
            AppLogger.application.notice("Spatial canvas unavailable because world tracking is unsupported")
            state = .unsupportedDevice
            return
        }

        var authorization = cameraPermissionService.authorizationStatus()
        if authorization == .notDetermined {
            AppLogger.permissions.info("Requesting camera access after a spatial canvas entry attempt")
            authorization = await cameraPermissionService.requestAccess()
        }

        updateState(for: authorization)
    }

    func refreshAfterApplicationBecomesActive() {
        guard state != .checking && state != .unsupportedDevice else {
            return
        }

        updateState(for: cameraPermissionService.authorizationStatus())
    }

    private func updateState(for authorization: CameraAuthorization) {
        switch authorization {
        case .authorized:
            state = .readyForCanvas
        case .notDetermined, .denied:
            state = .cameraAccessRequired
        case .restricted:
            state = .cameraAccessRestricted
        }
    }
}
