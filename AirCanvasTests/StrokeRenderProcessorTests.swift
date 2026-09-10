import simd
import XCTest
@testable import AirCanvas

final class StrokeRenderProcessorTests: XCTestCase {
    func testCompactionRemovesDuplicateAndDensePoints() throws {
        let processor = makeProcessor(minimumSpacing: 0.01, targetSegmentLength: 1)

        let points = processor.renderPoints(from: [
            try makeStrokePoint(x: 0, y: 0),
            try makeStrokePoint(x: 0, y: 0),
            try makeStrokePoint(x: 0.005, y: 0),
            try makeStrokePoint(x: 0.02, y: 0)
        ])

        XCTAssertEqual(points, [try makePoint(x: 0, y: 0), try makePoint(x: 0.02, y: 0)])
    }

    func testStraightLineRemainsStraightAndPreservesEndpoints() throws {
        let processor = makeProcessor(minimumSpacing: 0.01, targetSegmentLength: 0.025)
        let first = try makeStrokePoint(x: 0, y: 0)
        let last = try makeStrokePoint(x: 0.1, y: 0)

        let points = processor.renderPoints(from: [
            first,
            try makeStrokePoint(x: 0.05, y: 0),
            last
        ])

        XCTAssertEqual(points.first, first.position)
        XCTAssertEqual(points.last, last.position)
        XCTAssertTrue(points.allSatisfy { $0.y == 0 && $0.z == 0 })
    }

    func testSmoothingProducesOnlyFiniteCoordinates() throws {
        let processor = makeProcessor(minimumSpacing: 0.01, targetSegmentLength: 0.02)

        let points = processor.renderPoints(from: [
            try makeStrokePoint(x: 0, y: 0),
            try makeStrokePoint(x: 0.04, y: 0.06),
            try makeStrokePoint(x: 0.08, y: -0.04),
            try makeStrokePoint(x: 0.12, y: 0)
        ])

        XCTAssertTrue(points.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
    }

    func testInterpolationIsDeterministicAndBounded() throws {
        let processor = StrokeRenderProcessor(
            configuration: StrokeRenderConfiguration(
                minimumPointSpacing: 0.01,
                smoothingFactor: 1,
                targetSegmentLength: 0.01,
                maximumSegmentsPerInputPair: 3,
                maximumRenderablePointCount: 16
            )
        )
        let input = [try makeStrokePoint(x: 0, y: 0), try makeStrokePoint(x: 1, y: 0)]

        let firstResult = processor.renderPoints(from: input)
        let secondResult = processor.renderPoints(from: input)

        XCTAssertEqual(firstResult, secondResult)
        XCTAssertEqual(firstResult.count, 4)
        XCTAssertEqual(firstResult.first, input.first?.position)
        XCTAssertEqual(firstResult.last, input.last?.position)
    }

    func testInterpolationHonorsTotalRenderablePointCapWhilePreservingFinalPoint() throws {
        let processor = StrokeRenderProcessor(
            configuration: StrokeRenderConfiguration(
                minimumPointSpacing: 0.01,
                smoothingFactor: 1,
                targetSegmentLength: 0.01,
                maximumSegmentsPerInputPair: 16,
                maximumRenderablePointCount: 5
            )
        )
        let input = [
            try makeStrokePoint(x: 0, y: 0),
            try makeStrokePoint(x: 1, y: 0),
            try makeStrokePoint(x: 2, y: 0),
            try makeStrokePoint(x: 3, y: 0)
        ]

        let result = processor.renderPoints(from: input)

        XCTAssertLessThanOrEqual(result.count, 5)
        XCTAssertEqual(result.first, input.first?.position)
        XCTAssertEqual(result.last, input.last?.position)
    }

    func testTwoPointStrokeProducesValidTubeGeometry() throws {
        let stroke = try makeStroke(points: [
            try makeStrokePoint(x: 0, y: 0),
            try makeStrokePoint(x: 0.1, y: 0)
        ])
        let processor = makeProcessor(minimumSpacing: 0.01, targetSegmentLength: 1)
        let renderable = try XCTUnwrap(processor.renderableStroke(for: stroke))

        let geometry = try XCTUnwrap(StrokeTubeGeometryBuilder().geometry(for: renderable))

        XCTAssertFalse(geometry.positions.isEmpty)
        XCTAssertEqual(geometry.positions.count, geometry.normals.count)
        XCTAssertGreaterThan(geometry.triangleCount, 0)
        XCTAssertEqual(geometry.indices.count % 3, 0)
    }

    func testInsufficientOrCollapsedInputDoesNotProduceRenderableStroke() throws {
        let processor = makeProcessor(minimumSpacing: 0.01, targetSegmentLength: 1)
        let style = BrushStyle.defaultStyle
        let stroke = try Stroke(
            points: [
                try makeStrokePoint(x: 0, y: 0),
                try makeStrokePoint(x: 0, y: 0)
            ],
            style: style
        )

        XCTAssertNil(processor.renderableStroke(for: stroke))
    }

    func testThicknessMapsToTubeRadius() throws {
        let style = try BrushStyle(color: .defaultColor, thickness: 0.02)
        let stroke = try makeStroke(
            points: [try makeStrokePoint(x: 0, y: 0), try makeStrokePoint(x: 0.1, y: 0)],
            style: style
        )
        let renderable = try XCTUnwrap(makeProcessor(minimumSpacing: 0.01, targetSegmentLength: 1).renderableStroke(for: stroke))
        let geometry = try XCTUnwrap(StrokeTubeGeometryBuilder().geometry(for: renderable))

        let firstRingRadius = simd_length(SIMD2(geometry.positions[0].y, geometry.positions[0].z))
        XCTAssertEqual(firstRingRadius, 0.01, accuracy: 0.000_01)
    }

    func testProcessingPreservesStrokeIDAndColorStyle() throws {
        let color = try BrushColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 0.8)
        let style = try BrushStyle(color: color, thickness: 0.01)
        let identifier = UUID()
        let stroke = try Stroke(
            id: identifier,
            points: [try makeStrokePoint(x: 0, y: 0), try makeStrokePoint(x: 0.1, y: 0)],
            style: style
        )

        let renderable = try XCTUnwrap(makeProcessor(minimumSpacing: 0.01, targetSegmentLength: 1).renderableStroke(for: stroke))

        XCTAssertEqual(renderable.strokeID, identifier)
        XCTAssertEqual(renderable.style.color, color)
        XCTAssertEqual(renderable.style.thickness, style.thickness)
    }

    private func makeProcessor(minimumSpacing: Float, targetSegmentLength: Float) -> StrokeRenderProcessor {
        StrokeRenderProcessor(
            configuration: StrokeRenderConfiguration(
                minimumPointSpacing: minimumSpacing,
                smoothingFactor: 0.65,
                targetSegmentLength: targetSegmentLength,
                maximumSegmentsPerInputPair: 16,
                maximumRenderablePointCount: 1_024
            )
        )
    }

    private func makeStroke(points: [StrokePoint], style: BrushStyle = .defaultStyle) throws -> Stroke {
        try Stroke(points: points, style: style)
    }

    private func makeStrokePoint(x: Float, y: Float) throws -> StrokePoint {
        try StrokePoint(position: makePoint(x: x, y: y))
    }

    private func makePoint(x: Float, y: Float) throws -> CanvasPoint3D {
        try CanvasPoint3D(x: x, y: y, z: 0)
    }
}
