import ARKit

enum ARTrackingState: Equatable, Sendable {
    case initializing
    case normal
    case limited(ARTrackingLimitation)
    case unavailable

    init(cameraTrackingState: ARCamera.TrackingState) {
        switch cameraTrackingState {
        case .normal:
            self = .normal
        case .notAvailable:
            self = .unavailable
        case .limited(let reason):
            self = .limited(ARTrackingLimitation(reason: reason))
        }
    }

    var guidance: String? {
        switch self {
        case .initializing:
            "Move your device slowly to map your space."
        case .normal:
            nil
        case .limited(let limitation):
            limitation.guidance
        case .unavailable:
            "Spatial tracking is temporarily unavailable."
        }
    }
}

enum ARTrackingLimitation: Equatable, Sendable {
    case initializing
    case excessiveMotion
    case insufficientFeatures
    case relocalizing

    init(reason: ARCamera.TrackingState.Reason) {
        switch reason {
        case .initializing:
            self = .initializing
        case .excessiveMotion:
            self = .excessiveMotion
        case .insufficientFeatures:
            self = .insufficientFeatures
        case .relocalizing:
            self = .relocalizing
        @unknown default:
            self = .initializing
        }
    }

    var guidance: String {
        switch self {
        case .initializing:
            "Move your device slowly to map your space."
        case .excessiveMotion:
            "Move your device more slowly."
        case .insufficientFeatures:
            "Point toward a well-lit, textured area."
        case .relocalizing:
            "Relocalizing your space. Move slowly and look around."
        }
    }
}
