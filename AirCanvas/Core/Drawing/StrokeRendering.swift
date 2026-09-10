import CoreGraphics
import Foundation
import simd

@MainActor
protocol StrokeRendering: AnyObject {
    func beginActiveStroke(id: UUID, style: BrushStyle, firstPoint: StrokePoint)
    func appendActiveStrokePoint(
        strokeID: UUID,
        from previousPoint: StrokePoint,
        to point: StrokePoint,
        style: BrushStyle
    )
    @discardableResult
    func finalizeStroke(_ stroke: Stroke) -> Bool
    @discardableResult
    func renderStroke(_ stroke: Stroke) -> Bool
    @discardableResult
    func removeStroke(id: UUID) -> Bool
    func strokeID(at screenPoint: CGPoint) -> UUID?
    @discardableResult
    func setSelectedStrokeID(_ strokeID: UUID?) -> Bool
    @discardableResult
    func setHoveredStrokeID(_ strokeID: UUID?) -> Bool
    /// Applies a transient translation to an existing finalized stroke root. The
    /// Canvas model commits translated points only when hand manipulation ends.
    @discardableResult
    func setStrokeTranslation(_ translation: SIMD3<Float>, for strokeID: UUID) -> Bool
    /// Releases only derived, rebuildable renderer caches. It must never discard
    /// document strokes or currently rendered entities.
    func handleMemoryWarning()
    func clear()
}

extension StrokeRendering {
    func handleMemoryWarning() {}
}
