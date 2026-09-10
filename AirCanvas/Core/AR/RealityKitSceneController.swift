import ARKit
import RealityKit

@MainActor
final class RealityKitSceneController {
    private let session: ARSession
    private var arView: ARView?
    private var strokeRenderer: RealityKitStrokeRenderer?
    private var cursor: ModelEntity?

    init(session: ARSession) {
        self.session = session
    }

    func makeARView() -> ARView {
        if let arView {
            return arView
        }

        let arView = ARView(
            frame: .zero,
            cameraMode: .ar,
            automaticallyConfigureSession: false
        )
        arView.session = session
        self.arView = arView
        strokeRenderer = RealityKitStrokeRenderer(arView: arView)
        return arView
    }

    func makeStrokeRenderer() -> any StrokeRendering {
        if let strokeRenderer {
            return strokeRenderer
        }

        _ = makeARView()
        guard let strokeRenderer else {
            preconditionFailure("AR view creation must create a stroke renderer.")
        }
        return strokeRenderer
    }

    func updateSpatialCursor(position: SIMD3<Float>?, isPinching: Bool) {
        guard let position else { cursor?.isEnabled = false; return }
        let arView = makeARView()
        let cursor = cursor ?? {
            let entity = ModelEntity(mesh: .generateSphere(radius: 0.012), materials: [SimpleMaterial(color: .cyan, isMetallic: true)])
            arView.scene.addAnchor(AnchorEntity(world: .zero))
            arView.scene.anchors[arView.scene.anchors.count - 1].addChild(entity)
            self.cursor = entity; return entity
        }()
        cursor.position = position; cursor.isEnabled = true
        cursor.model?.materials = [SimpleMaterial(color: isPinching ? .green : .cyan, isMetallic: true)]
    }
    func clearSpatialCursor() { cursor?.removeFromParent(); cursor = nil }
}

extension RealityKitSceneController: SpatialCursorRendering {}
