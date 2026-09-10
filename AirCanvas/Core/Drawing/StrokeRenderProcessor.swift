import Foundation
import simd

/// Rendering-only tuning values. They never alter the canonical `Stroke` data.
struct StrokeRenderConfiguration: Equatable, Sendable {
    static let standard = StrokeRenderConfiguration(
        minimumPointSpacing: 0.005,
        smoothingFactor: 0.65,
        targetSegmentLength: 0.015,
        maximumSegmentsPerInputPair: 16,
        maximumRenderablePointCount: 1_024
    )

    let minimumPointSpacing: Float
    let smoothingFactor: Float
    let targetSegmentLength: Float
    let maximumSegmentsPerInputPair: Int
    let maximumRenderablePointCount: Int

    init(
        minimumPointSpacing: Float,
        smoothingFactor: Float,
        targetSegmentLength: Float,
        maximumSegmentsPerInputPair: Int,
        maximumRenderablePointCount: Int
    ) {
        self.minimumPointSpacing = minimumPointSpacing
        self.smoothingFactor = smoothingFactor
        self.targetSegmentLength = targetSegmentLength
        self.maximumSegmentsPerInputPair = maximumSegmentsPerInputPair
        self.maximumRenderablePointCount = maximumRenderablePointCount
    }

    func isValid() -> Bool {
        minimumPointSpacing.isFinite && minimumPointSpacing > 0
            && smoothingFactor.isFinite && (0 ... 1).contains(smoothingFactor)
            && targetSegmentLength.isFinite && targetSegmentLength > 0
            && maximumSegmentsPerInputPair >= 1
            && maximumRenderablePointCount >= 2
    }
}

/// A runtime rendering input derived from, but separate from, persistent stroke data.
struct RenderableStroke: Equatable, Sendable {
    let strokeID: UUID
    let points: [CanvasPoint3D]
    let style: BrushStyle
}

/// Pure, deterministic processing for render-friendly stroke paths.
struct StrokeRenderProcessor: Sendable {
    let configuration: StrokeRenderConfiguration

    init(configuration: StrokeRenderConfiguration = .standard) {
        precondition(configuration.isValid(), "StrokeRenderConfiguration must be valid.")
        self.configuration = configuration
    }

    func renderableStroke(for stroke: Stroke) -> RenderableStroke? {
        let points = renderPoints(from: stroke.points)
        guard points.count >= 2 else {
            return nil
        }

        return RenderableStroke(strokeID: stroke.id, points: points, style: stroke.style)
    }

    func renderPoints(from rawPoints: [StrokePoint]) -> [CanvasPoint3D] {
        let compacted = limit(compact(rawPoints.map(\.position)))
        guard compacted.count >= 2 else {
            return compacted
        }

        return interpolate(smooth(compacted))
    }

    private func compact(_ points: [CanvasPoint3D]) -> [CanvasPoint3D] {
        guard let first = points.first else {
            return []
        }

        var compacted = [first]
        for point in points.dropFirst() {
            guard let previous = compacted.last else {
                continue
            }
            guard distance(from: previous, to: point) >= configuration.minimumPointSpacing else {
                continue
            }
            compacted.append(point)
        }
        return compacted
    }

    private func limit(_ points: [CanvasPoint3D]) -> [CanvasPoint3D] {
        guard points.count > configuration.maximumRenderablePointCount else {
            return points
        }

        let finalIndex = points.count - 1
        let outputFinalIndex = configuration.maximumRenderablePointCount - 1
        return (0 ... outputFinalIndex).map { outputIndex in
            let fraction = Float(outputIndex) / Float(outputFinalIndex)
            return points[Int((fraction * Float(finalIndex)).rounded())]
        }
    }

    private func smooth(_ points: [CanvasPoint3D]) -> [CanvasPoint3D] {
        guard points.count > 2 else {
            return points
        }

        var smoothed = [points[0]]
        for point in points.dropFirst().dropLast() {
            guard let previous = smoothed.last else {
                continue
            }
            smoothed.append(blend(from: previous, to: point, factor: configuration.smoothingFactor))
        }
        smoothed.append(points[points.count - 1])
        return smoothed
    }

    private func interpolate(_ points: [CanvasPoint3D]) -> [CanvasPoint3D] {
        guard let first = points.first else {
            return []
        }

        var interpolated = [first]
        let pairCount = points.count - 1
        for (pairIndex, pair) in zip(points, points.dropFirst()).enumerated() {
            let (start, end) = pair
            let distance = distance(from: start, to: end)
            let requestedSegments = max(1, Int(ceil(distance / configuration.targetSegmentLength)))
            let maximumSegmentsForPair = configuration.maximumRenderablePointCount
                - interpolated.count
                - (pairCount - pairIndex - 1)
            let segmentCount = min(
                requestedSegments,
                configuration.maximumSegmentsPerInputPair,
                max(1, maximumSegmentsForPair)
            )

            for segment in 1 ... segmentCount {
                let fraction = Float(segment) / Float(segmentCount)
                interpolated.append(blend(from: start, to: end, factor: fraction))
            }
        }
        return interpolated
    }

    private func distance(from start: CanvasPoint3D, to end: CanvasPoint3D) -> Float {
        simd_distance(start.simdValue, end.simdValue)
    }

    private func blend(from start: CanvasPoint3D, to end: CanvasPoint3D, factor: Float) -> CanvasPoint3D {
        let position = start.simdValue + ((end.simdValue - start.simdValue) * factor)
        // Both inputs are validated finite values and factor is validated in 0...1.
        return CanvasPoint3D(uncheckedSIMDValue: position)
    }
}

extension CanvasPoint3D {
    fileprivate init(uncheckedSIMDValue value: SIMD3<Float>) {
        x = value.x
        y = value.y
        z = value.z
    }
}
