import RealityKit
import UIKit

@MainActor
final class RealityKitStrokeRenderer: StrokeRendering {
    private enum Representation {
        case active(segmentCount: Int)
        case finalized(renderablePointCount: Int)
    }

    private struct RenderedStroke {
        let root: Entity
        let material: SimpleMaterial
        let color: BrushColor
        let modelEntity: ModelEntity?
        var representation: Representation
    }

    private weak var arView: ARView?
    private let processor: StrokeRenderProcessor
    private let geometryBuilder: StrokeTubeGeometryBuilder
    private var drawingAnchor: AnchorEntity?
    private var renderedStrokes: [UUID: RenderedStroke] = [:]
    private var materialCache: [BrushColor: SimpleMaterial] = [:]
    private var selectionMaterialCache: [BrushColor: SimpleMaterial] = [:]
    private var selectedStrokeID: UUID?
    private var hoveredStrokeID: UUID?

    init(
        arView: ARView,
        processor: StrokeRenderProcessor = StrokeRenderProcessor(),
        geometryBuilder: StrokeTubeGeometryBuilder = StrokeTubeGeometryBuilder()
    ) {
        self.arView = arView
        self.processor = processor
        self.geometryBuilder = geometryBuilder
    }

    func beginActiveStroke(id: UUID, style: BrushStyle, firstPoint _: StrokePoint) {
        guard let drawingAnchor = ensureDrawingAnchor() else {
            return
        }

        removeStroke(id: id)

        let root = Entity()
        drawingAnchor.addChild(root)
        renderedStrokes[id] = RenderedStroke(
            root: root,
            material: material(for: style),
            color: style.color,
            modelEntity: nil,
            representation: .active(segmentCount: 0)
        )
    }

    func appendActiveStrokePoint(
        strokeID: UUID,
        from previousPoint: StrokePoint,
        to point: StrokePoint,
        style: BrushStyle
    ) {
        guard var renderedStroke = renderedStrokes[strokeID] else {
            return
        }

        let activeStroke = RenderableStroke(
            strokeID: strokeID,
            points: [previousPoint.position, point.position],
            style: style
        )
        guard let mesh = meshResource(for: activeStroke) else {
            return
        }

        renderedStroke.root.addChild(ModelEntity(mesh: mesh, materials: [renderedStroke.material]))
        if case .active(let segmentCount) = renderedStroke.representation {
            renderedStroke.representation = .active(segmentCount: segmentCount + 1)
        }
        renderedStrokes[strokeID] = renderedStroke
    }

    @discardableResult
    func finalizeStroke(_ stroke: Stroke) -> Bool {
        let startedAt = ProcessInfo.processInfo.systemUptime
        guard var renderedStroke = renderedStrokes[stroke.id] else {
            return renderStroke(stroke)
        }

        guard let renderableStroke = processor.renderableStroke(for: stroke) else {
            AppLogger.drawing.error("Completed stroke could not produce renderable points")
            removeStroke(id: stroke.id)
            return false
        }
        guard let mesh = meshResource(for: renderableStroke) else {
            AppLogger.drawing.error("Completed stroke could not produce a RealityKit mesh")
            return false
        }

        removeChildren(from: renderedStroke.root)
        let modelEntity = makeSelectableModelEntity(mesh: mesh, material: renderedStroke.material)
        renderedStroke.root.addChild(modelEntity)
        renderedStroke = RenderedStroke(
            root: renderedStroke.root,
            material: renderedStroke.material,
            color: renderedStroke.color,
            modelEntity: modelEntity,
            representation: .finalized(renderablePointCount: renderableStroke.points.count)
        )
        renderedStrokes[stroke.id] = renderedStroke
#if DEBUG
        AppLogger.performance.debug(
            "Finalized stroke renderer update: points=\(renderableStroke.points.count, privacy: .public), duration=\(ProcessInfo.processInfo.systemUptime - startedAt, privacy: .public)s"
        )
#endif
        logDiagnosticsIfNeeded()
        return true
    }

    @discardableResult
    func renderStroke(_ stroke: Stroke) -> Bool {
        let startedAt = ProcessInfo.processInfo.systemUptime
        guard let drawingAnchor = ensureDrawingAnchor() else {
            return false
        }
        guard let renderableStroke = processor.renderableStroke(for: stroke) else {
            AppLogger.drawing.error("Stored stroke could not produce renderable points")
            return false
        }
        guard let mesh = meshResource(for: renderableStroke) else {
            AppLogger.drawing.error("Stored stroke could not produce a RealityKit mesh")
            return false
        }

        removeStroke(id: stroke.id)
        let root = Entity()
        let material = material(for: stroke.style)
        let modelEntity = makeSelectableModelEntity(mesh: mesh, material: material)
        root.addChild(modelEntity)
        drawingAnchor.addChild(root)
        renderedStrokes[stroke.id] = RenderedStroke(
            root: root,
            material: material,
            color: stroke.style.color,
            modelEntity: modelEntity,
            representation: .finalized(renderablePointCount: renderableStroke.points.count)
        )
#if DEBUG
        AppLogger.performance.debug(
            "Restored stroke renderer update: points=\(renderableStroke.points.count, privacy: .public), duration=\(ProcessInfo.processInfo.systemUptime - startedAt, privacy: .public)s"
        )
#endif
        logDiagnosticsIfNeeded()
        return true
    }

    @discardableResult
    func removeStroke(id: UUID) -> Bool {
        guard let renderedStroke = renderedStrokes.removeValue(forKey: id) else {
            return false
        }

        if selectedStrokeID == id {
            selectedStrokeID = nil
        }
        if hoveredStrokeID == id {
            hoveredStrokeID = nil
        }
        renderedStroke.root.removeFromParent()
        logDiagnosticsIfNeeded()
        return true
    }

    func strokeID(at screenPoint: CGPoint) -> UUID? {
        guard let arView, let hitEntity = arView.entity(at: screenPoint) else {
            return nil
        }
        return strokeID(for: hitEntity)
    }

    @discardableResult
    func setSelectedStrokeID(_ strokeID: UUID?) -> Bool {
        if selectedStrokeID == strokeID {
            guard let strokeID else {
                return true
            }
            return renderedStrokes[strokeID] != nil
        }

        if let selectedStrokeID, let renderedStroke = renderedStrokes[selectedStrokeID] {
            applySelectionHighlight(false, to: renderedStroke)
        }
        selectedStrokeID = nil

        guard let strokeID else {
            return true
        }
        guard let renderedStroke = renderedStrokes[strokeID], renderedStroke.modelEntity != nil else {
            return false
        }

        applySelectionHighlight(true, to: renderedStroke)
        selectedStrokeID = strokeID
        return true
    }

    @discardableResult
    func setHoveredStrokeID(_ strokeID: UUID?) -> Bool {
        if hoveredStrokeID == strokeID {
            guard let strokeID else { return true }
            return renderedStrokes[strokeID] != nil
        }
        if let previous = hoveredStrokeID, previous != selectedStrokeID,
           let renderedStroke = renderedStrokes[previous] {
            applySelectionHighlight(false, to: renderedStroke)
        }
        hoveredStrokeID = nil
        guard let strokeID else { return true }
        guard renderedStrokes[strokeID] != nil else { return false }
        if strokeID != selectedStrokeID, let renderedStroke = renderedStrokes[strokeID] {
            applySelectionHighlight(true, to: renderedStroke)
        }
        hoveredStrokeID = strokeID
        return true
    }

    @discardableResult
    func setStrokeTranslation(_ translation: SIMD3<Float>, for strokeID: UUID) -> Bool {
        guard translation.x.isFinite, translation.y.isFinite, translation.z.isFinite,
              let renderedStroke = renderedStrokes[strokeID] else {
            return false
        }
        renderedStroke.root.position = translation
        return true
    }

    func clear() {
        drawingAnchor?.removeFromParent()
        drawingAnchor = nil
        renderedStrokes.removeAll()
        materialCache.removeAll()
        selectionMaterialCache.removeAll()
        selectedStrokeID = nil
        hoveredStrokeID = nil
        logDiagnosticsIfNeeded()
    }

    func handleMemoryWarning() {
        // Finalized entities retain their own materials. These dictionaries are
        // only factories for future strokes/highlights and can be rebuilt safely.
        materialCache.removeAll(keepingCapacity: false)
        selectionMaterialCache.removeAll(keepingCapacity: false)
        AppLogger.performance.notice("Released rebuildable RealityKit material caches after memory warning")
    }

    private func ensureDrawingAnchor() -> AnchorEntity? {
        if let drawingAnchor {
            return drawingAnchor
        }
        guard let arView else {
            AppLogger.ar.error("Stroke rendering requested without an AR view")
            return nil
        }

        let drawingAnchor = AnchorEntity(world: .zero)
        arView.scene.addAnchor(drawingAnchor)
        self.drawingAnchor = drawingAnchor
        return drawingAnchor
    }

    private func meshResource(for stroke: RenderableStroke) -> MeshResource? {
        guard let geometry = geometryBuilder.geometry(for: stroke) else {
            return nil
        }

        var descriptor = MeshDescriptor()
        descriptor.positions = MeshBuffers.Positions(geometry.positions)
        descriptor.normals = MeshBuffers.Normals(geometry.normals)
        descriptor.primitives = .triangles(geometry.indices)

        do {
            return try MeshResource.generate(from: [descriptor])
        } catch {
            AppLogger.drawing.error("Stroke mesh generation failed: \(error.localizedDescription, privacy: .private(mask: .hash))")
            return nil
        }
    }

    private func material(for style: BrushStyle) -> SimpleMaterial {
        if let material = materialCache[style.color] {
            return material
        }

        let material = SimpleMaterial(
            color: UIColor(
                red: CGFloat(style.color.red),
                green: CGFloat(style.color.green),
                blue: CGFloat(style.color.blue),
                alpha: CGFloat(style.color.alpha)
            ),
            isMetallic: false
        )
        materialCache[style.color] = material
        return material
    }

    private func selectionMaterial(for color: BrushColor) -> SimpleMaterial {
        if let material = selectionMaterialCache[color] {
            return material
        }

        let highlightColor = UIColor(
            red: CGFloat(min(1, color.red * 0.45 + 0.55)),
            green: CGFloat(min(1, color.green * 0.45 + 0.55)),
            blue: CGFloat(min(1, color.blue * 0.2 + 0.8)),
            alpha: 1
        )
        let material = SimpleMaterial(color: highlightColor, isMetallic: true)
        selectionMaterialCache[color] = material
        return material
    }

    private func makeSelectableModelEntity(mesh: MeshResource, material: SimpleMaterial) -> ModelEntity {
        let modelEntity = ModelEntity(mesh: mesh, materials: [material])
        modelEntity.generateCollisionShapes(recursive: false)
        return modelEntity
    }

    private func strokeID(for entity: Entity) -> UUID? {
        var candidate: Entity? = entity
        while let current = candidate {
            if let match = renderedStrokes.first(where: { $0.value.root === current }) {
                return match.key
            }
            candidate = current.parent
        }
        return nil
    }

    private func applySelectionHighlight(_ isSelected: Bool, to renderedStroke: RenderedStroke) {
        guard let modelEntity = renderedStroke.modelEntity else {
            return
        }
        modelEntity.model?.materials = [
            isSelected ? selectionMaterial(for: renderedStroke.color) : renderedStroke.material
        ]
    }

    private func removeChildren(from entity: Entity) {
        for child in entity.children {
            child.removeFromParent()
        }
    }

    #if DEBUG
    private func logDiagnosticsIfNeeded() {
        let activeSegmentCount = renderedStrokes.values.reduce(into: 0) { count, stroke in
            if case .active(let segmentCount) = stroke.representation {
                count += segmentCount
            }
        }
        let finalizedPointCount = renderedStrokes.values.reduce(into: 0) { count, stroke in
            if case .finalized(let renderablePointCount) = stroke.representation {
                count += renderablePointCount
            }
        }
        AppLogger.drawing.debug(
            "Stroke renderer diagnostics: strokes=\(self.renderedStrokes.count, privacy: .public), activeSegments=\(activeSegmentCount, privacy: .public), finalizedPoints=\(finalizedPointCount, privacy: .public)"
        )
    }
    #else
    private func logDiagnosticsIfNeeded() {}
    #endif
}
