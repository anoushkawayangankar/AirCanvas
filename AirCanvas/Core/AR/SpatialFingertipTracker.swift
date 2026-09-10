import CoreGraphics
import Foundation
import simd

enum SpatialFingertipState: Equatable, Sendable { case unavailable, searching, tracked(SIMD3<Float>) }

struct WorldPointSmoother: Sendable {
    private var value: SIMD3<Float>?
    mutating func update(_ point: SIMD3<Float>) -> SIMD3<Float> { guard let value else { self.value = point; return point }; let output = value + 0.35 * (point - value); self.value = output; return output }
    mutating func reset() { value = nil }
}

@MainActor protocol SpatialCursorRendering: AnyObject { func updateSpatialCursor(position: SIMD3<Float>?, isPinching: Bool) }
