import Foundation
import simd

/// Framework-independent nearest-polyline lookup for world-space hand interaction.
struct SpatialStrokeHitTester: Sendable {
    struct Configuration: Equatable, Sendable {
        /// Initial hand-selection radius in metres. It is intentionally centralized
        /// for future physical-device tuning.
        let selectionRadius: Float

        init(selectionRadius: Float = 0.08) {
            precondition(selectionRadius.isFinite && selectionRadius > 0)
            self.selectionRadius = selectionRadius
        }
    }

    let configuration: Configuration

    init(configuration: Configuration = .init()) {
        self.configuration = configuration
    }

    /// Returns the nearest eligible stroke. Equal-distance candidates retain their
    /// document order, producing stable hover behavior for overlapping strokes.
    func nearestStrokeID(to worldPoint: SIMD3<Float>, in strokes: [Stroke]) -> Stroke.ID? {
        guard isFinite(worldPoint) else { return nil }

        var nearestID: Stroke.ID?
        var nearestDistance = configuration.selectionRadius

        for stroke in strokes {
            guard let bounds = stroke.spatialBounds,
                  distance(from: worldPoint, to: bounds) <= nearestDistance else {
                continue
            }
            guard let distance = distance(from: worldPoint, to: stroke), distance.isFinite else {
                continue
            }
            if distance <= nearestDistance {
                // Strict comparison intentionally leaves an equal-distance earlier
                // document entry selected.
                if nearestID == nil || distance < nearestDistance {
                    nearestID = stroke.id
                    nearestDistance = distance
                }
            }
        }
        return nearestID
    }

    func distance(from point: SIMD3<Float>, to stroke: Stroke) -> Float? {
        guard isFinite(point), !stroke.points.isEmpty else { return nil }
        guard let first = stroke.points.first?.position.simdValue, isFinite(first) else { return nil }
        guard stroke.points.count > 1 else { return simd_distance(point, first) }

        var minimumDistance = Float.infinity
        var start = first
        for strokePoint in stroke.points.dropFirst() {
            let end = strokePoint.position.simdValue
            guard let distance = distance(from: point, toSegmentFrom: start, to: end) else {
                return nil
            }
            minimumDistance = min(minimumDistance, distance)
            start = end
        }
        return minimumDistance.isFinite ? minimumDistance : nil
    }

    func distance(from point: SIMD3<Float>, toSegmentFrom start: SIMD3<Float>, to end: SIMD3<Float>) -> Float? {
        guard isFinite(point), isFinite(start), isFinite(end) else { return nil }
        let segment = end - start
        let lengthSquared = simd_length_squared(segment)
        guard lengthSquared.isFinite else { return nil }
        guard lengthSquared > .ulpOfOne else { return simd_distance(point, start) }

        let projection = simd_dot(point - start, segment) / lengthSquared
        guard projection.isFinite else { return nil }
        let closestPoint = start + min(max(projection, 0), 1) * segment
        let distance = simd_distance(point, closestPoint)
        return distance.isFinite ? distance : nil
    }

    private func isFinite(_ point: SIMD3<Float>) -> Bool {
        point.x.isFinite && point.y.isFinite && point.z.isFinite
    }
}

struct StrokeSpatialBounds: Equatable, Sendable {
    let minimum: SIMD3<Float>
    let maximum: SIMD3<Float>
}

extension Stroke {
    /// Derived, non-persisted bounds used only as a conservative hit-test
    /// prefilter. Geometry remains the authority for a positive hit.
    var spatialBounds: StrokeSpatialBounds? {
        guard let first = points.first?.position.simdValue,
              first.x.isFinite, first.y.isFinite, first.z.isFinite else { return nil }
        var minimum = first
        var maximum = first
        for point in points.dropFirst() {
            let value = point.position.simdValue
            guard value.x.isFinite, value.y.isFinite, value.z.isFinite else { return nil }
            minimum = SIMD3(
                min(minimum.x, value.x),
                min(minimum.y, value.y),
                min(minimum.z, value.z)
            )
            maximum = SIMD3(
                max(maximum.x, value.x),
                max(maximum.y, value.y),
                max(maximum.z, value.z)
            )
        }
        return StrokeSpatialBounds(minimum: minimum, maximum: maximum)
    }
}

private extension SpatialStrokeHitTester {
    func distance(from point: SIMD3<Float>, to bounds: StrokeSpatialBounds) -> Float {
        let clamped = SIMD3(
            min(max(point.x, bounds.minimum.x), bounds.maximum.x),
            min(max(point.y, bounds.minimum.y), bounds.maximum.y),
            min(max(point.z, bounds.minimum.z), bounds.maximum.z)
        )
        return simd_distance(point, clamped)
    }
}

extension Stroke {
    /// Produces an ID/style/timestamp-preserving world-space translation. Preview
    /// rendering always derives from the original stroke to avoid accumulated drift.
    func translated(by translation: SIMD3<Float>) -> Stroke? {
        guard translation.x.isFinite, translation.y.isFinite, translation.z.isFinite else {
            return nil
        }

        let translatedPoints = points.compactMap { point -> StrokePoint? in
            guard let position = try? CanvasPoint3D(simdValue: point.position.simdValue + translation) else {
                return nil
            }
            return try? StrokePoint(position: position, timestamp: point.timestamp)
        }
        guard translatedPoints.count == points.count else { return nil }
        return try? Stroke(id: id, points: translatedPoints, style: style, createdAt: createdAt)
    }
}
