import ARKit

enum SpatialCanvasCapability: Equatable, Sendable {
    case supported
    case unsupportedWorldTracking
}

protocol SpatialCanvasCapabilityChecking {
    func spatialCanvasCapability() -> SpatialCanvasCapability
}

struct SpatialCanvasCapabilityService: SpatialCanvasCapabilityChecking {
    func spatialCanvasCapability() -> SpatialCanvasCapability {
        ARWorldTrackingConfiguration.isSupported ? .supported : .unsupportedWorldTracking
    }
}
