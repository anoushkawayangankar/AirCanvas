import Foundation
import simd

/// Pure, framework-independent geometry operations for completed strokes.
struct StrokeTransformer: Sendable {
    struct Configuration: Equatable, Sendable {
        static let standard = Configuration(minScale: 0.25, maxScale: 4.0)
        let minScale: Float
        let maxScale: Float

        init(minScale: Float, maxScale: Float) {
            precondition(minScale.isFinite && maxScale.isFinite && minScale > 0 && maxScale >= minScale)
            self.minScale = minScale
            self.maxScale = maxScale
        }

        func clampedScale(_ scale: Float) -> Float? {
            guard scale.isFinite, scale > 0 else { return nil }
            return min(max(scale, minScale), maxScale)
        }
    }

    let configuration: Configuration

    init(configuration: Configuration = .standard) {
        self.configuration = configuration
    }

    func centroid(of stroke: Stroke) -> CanvasPoint3D? {
        guard !stroke.points.isEmpty else { return nil }
        let sum = stroke.points.reduce(SIMD3<Float>.zero) { $0 + $1.position.simdValue }
        let center = sum / Float(stroke.points.count)
        guard center.x.isFinite, center.y.isFinite, center.z.isFinite else { return nil }
        return try? CanvasPoint3D(simdValue: center)
    }

    func scale(_ stroke: Stroke, by scale: Float, around pivot: CanvasPoint3D? = nil) -> Stroke? {
        guard let scale = configuration.clampedScale(scale), let pivot = pivot ?? centroid(of: stroke) else { return nil }
        return transform(stroke, pivot: pivot) { $0 * scale }
    }

    /// Rotates around the world-up (Y) axis, in radians.
    func rotate(_ stroke: Stroke, by angle: Float, around pivot: CanvasPoint3D? = nil) -> Stroke? {
        guard angle.isFinite, let pivot = pivot ?? centroid(of: stroke) else { return nil }
        let rotation = simd_float3x3(simd_quatf(angle: angle, axis: SIMD3<Float>(0, 1, 0)))
        return transform(stroke, pivot: pivot) { rotation * $0 }
    }

    private func transform(_ stroke: Stroke, pivot: CanvasPoint3D, operation: (SIMD3<Float>) -> SIMD3<Float>) -> Stroke? {
        let pivotValue = pivot.simdValue
        guard pivotValue.x.isFinite, pivotValue.y.isFinite, pivotValue.z.isFinite else { return nil }
        var points: [StrokePoint] = []
        points.reserveCapacity(stroke.points.count)
        for point in stroke.points {
            let value = operation(point.position.simdValue - pivotValue) + pivotValue
            guard value.x.isFinite, value.y.isFinite, value.z.isFinite,
                  let canvasPoint = try? CanvasPoint3D(simdValue: value),
                  let transformedPoint = try? StrokePoint(position: canvasPoint, timestamp: point.timestamp) else { return nil }
            points.append(transformedPoint)
        }
        return try? Stroke(id: stroke.id, points: points, style: stroke.style, createdAt: stroke.createdAt)
    }
}
