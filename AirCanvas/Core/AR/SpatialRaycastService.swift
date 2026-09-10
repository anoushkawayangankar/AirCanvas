import ARKit
import CoreGraphics
import RealityKit

@MainActor
protocol SpatialRaycasting: AnyObject {
    func raycast(at screenPoint: CGPoint) -> SpatialRaycastResult?
}

@MainActor
final class SpatialRaycastService: SpatialRaycasting {
    private weak var arView: ARView?

    init(arView: ARView) {
        self.arView = arView
    }

    func raycast(at screenPoint: CGPoint) -> SpatialRaycastResult? {
        guard let arView else {
            AppLogger.ar.error("Spatial raycast requested without an AR view")
            return nil
        }

        if let result = arView.raycast(
            from: screenPoint,
            allowing: .existingPlaneGeometry,
            alignment: .any
        ).first {
            AppLogger.ar.debug("Spatial raycast succeeded using existing plane geometry")
            return SpatialRaycastResult(
                worldTransform: result.worldTransform,
                source: .existingPlaneGeometry
            )
        }

        if let result = arView.raycast(
            from: screenPoint,
            allowing: .estimatedPlane,
            alignment: .any
        ).first {
            AppLogger.ar.debug("Spatial raycast succeeded using an estimated plane")
            return SpatialRaycastResult(
                worldTransform: result.worldTransform,
                source: .estimatedPlane
            )
        }

        AppLogger.ar.debug("Spatial raycast found no valid surface")
        return nil
    }
}
