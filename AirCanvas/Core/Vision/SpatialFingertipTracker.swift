import Foundation
import simd

enum SpatialFingertipState: Equatable, Sendable { case unavailable, searching, tracked(SIMD3<Float>) }

struct WorldPointSmoother: Sendable {
    private var value: SIMD3<Float>?
    mutating func update(_ point: SIMD3<Float>) -> SIMD3<Float> { guard let value else { self.value = point; return point }; let output = value + 0.35 * (point - value); self.value = output; return output }
    mutating func reset() { value = nil }
}

struct SpatialFingertipConfiguration: Sendable { let maximumJump: Float = 0.45 }

struct SpatialFingertipProcessor: Sendable {
    private var smoother = WorldPointSmoother()
    private var previous: SIMD3<Float>?
    let configuration = SpatialFingertipConfiguration()
    mutating func accept(_ point: SIMD3<Float>) -> SIMD3<Float>? {
        guard point.x.isFinite, point.y.isFinite, point.z.isFinite else { return nil }
        if let previous, simd_distance(previous, point) > configuration.maximumJump { return nil }
        previous = point; return smoother.update(point)
    }
    mutating func reset() { previous = nil; smoother.reset() }
}

@MainActor protocol SpatialCursorRendering: AnyObject { func updateSpatialCursor(position: SIMD3<Float>?, isPinching: Bool) }
