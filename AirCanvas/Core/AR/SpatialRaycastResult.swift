import simd

/// A runtime-only world-space result produced from an AR screen-space raycast.
/// It deliberately contains no ARKit object so future drawing and input features
/// can consume the coordinate without retaining framework state.
struct SpatialRaycastResult: Sendable {
    let worldTransform: simd_float4x4
    let worldPosition: SIMD3<Float>
    let source: SpatialRaycastSource

    init(worldTransform: simd_float4x4, source: SpatialRaycastSource) {
        self.worldTransform = worldTransform
        worldPosition = SIMD3(
            worldTransform.columns.3.x,
            worldTransform.columns.3.y,
            worldTransform.columns.3.z
        )
        self.source = source
    }
}

enum SpatialRaycastSource: Equatable, Sendable {
    case existingPlaneGeometry
    case estimatedPlane
}

enum SpatialRaycastReadiness: Equatable, Sendable {
    case ready
    case unavailable(guidance: String)

    init(trackingState: ARTrackingState) {
        switch trackingState {
        case .normal:
            self = .ready
        case .initializing, .limited, .unavailable:
            self = .unavailable(
                guidance: trackingState.guidance ?? "Move your device slowly to map your space."
            )
        }
    }
}
