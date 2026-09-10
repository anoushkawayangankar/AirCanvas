import CoreGraphics
import Foundation

enum FingertipTrackingState: Equatable, Sendable {
    case unavailable
    case tracking(CGPoint)
}

struct VisionCoordinateConverter: Sendable {
    /// Vision points are normalized from the lower-left image origin. The portrait AR preview uses a top-left display origin.
    func displayPoint(from visionNormalizedPoint: CGPoint, viewportSize: CGSize) -> CGPoint? {
        guard visionNormalizedPoint.x.isFinite, visionNormalizedPoint.y.isFinite,
              (0 ... 1).contains(visionNormalizedPoint.x), (0 ... 1).contains(visionNormalizedPoint.y),
              viewportSize.width > 0, viewportSize.height > 0 else { return nil }
        return CGPoint(x: visionNormalizedPoint.x * viewportSize.width, y: (1 - visionNormalizedPoint.y) * viewportSize.height)
    }
}

struct PointSmoother: Sendable {
    let factor: CGFloat
    private(set) var value: CGPoint?

    init(factor: CGFloat = 0.35) { self.factor = min(max(factor, 0.05), 1) }
    mutating func update(_ point: CGPoint) -> CGPoint {
        guard let value else { self.value = point; return point }
        let result = CGPoint(x: value.x + factor * (point.x - value.x), y: value.y + factor * (point.y - value.y))
        self.value = result; return result
    }
    mutating func reset() { value = nil }
}

@MainActor @Observable final class FingertipCursorModel {
    private let converter = VisionCoordinateConverter()
    private var smoother = PointSmoother()
    private var viewportSize = CGSize.zero
    private(set) var state: FingertipTrackingState = .unavailable

    func updateViewportSize(_ size: CGSize) { viewportSize = size }
    func consume(_ handState: HandTrackingState) {
        guard case .detected(let pose) = handState,
              let displayPoint = converter.displayPoint(from: pose.indexTip.normalizedPosition, viewportSize: viewportSize) else { hide(); return }
        state = .tracking(smoother.update(displayPoint))
    }
    func hide() { smoother.reset(); state = .unavailable }
}
