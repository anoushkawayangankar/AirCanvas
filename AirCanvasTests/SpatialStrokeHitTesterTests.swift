import simd
import XCTest
@testable import AirCanvas

final class SpatialStrokeHitTesterTests: XCTestCase {
    private let tester = SpatialStrokeHitTester(
        configuration: .init(selectionRadius: 0.1)
    )

    func testPointNearSegmentReturnsExpectedDistance() throws {
        let distance = try XCTUnwrap(
            tester.distance(from: SIMD3(0.5, 0.05, 0), toSegmentFrom: .zero, to: SIMD3(1, 0, 0))
        )
        XCTAssertEqual(
            distance,
            0.05,
            accuracy: 0.0001
        )
    }

    func testProjectionBeforeAndAfterSegmentUseEndpoints() {
        XCTAssertEqual(tester.distance(from: SIMD3(-1, 0, 0), toSegmentFrom: .zero, to: SIMD3(1, 0, 0)), 1)
        XCTAssertEqual(tester.distance(from: SIMD3(2, 0, 0), toSegmentFrom: .zero, to: SIMD3(1, 0, 0)), 1)
    }

    func testZeroLengthSegmentIsHandledAsAPoint() {
        XCTAssertEqual(tester.distance(from: SIMD3(0, 0.2, 0), toSegmentFrom: .zero, to: .zero), 0.2)
    }

    func testNearestStrokeUsesPolylineGeometryAndStableDocumentTieBreak() throws {
        let first = try stroke(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, points: [(0, 0), (1, 0)])
        let second = try stroke(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, points: [(0, 0.04), (1, 0.04)])

        XCTAssertEqual(tester.nearestStrokeID(to: SIMD3(0.5, 0.04, 0), in: [first, second]), second.id)
        XCTAssertEqual(tester.nearestStrokeID(to: SIMD3(0.5, 0.02, 0), in: [first, second]), first.id)
    }

    func testMultiSegmentStrokeFindsNearestSegmentAndRejectsOutsideThreshold() throws {
        let stroke = try stroke(points: [(0, 0), (1, 0), (1, 1)])
        XCTAssertEqual(tester.nearestStrokeID(to: SIMD3(1.04, 0.7, 0), in: [stroke]), stroke.id)
        XCTAssertNil(tester.nearestStrokeID(to: SIMD3(1.3, 0.7, 0), in: [stroke]))
    }

    func testNonFiniteInputAndTranslationAreRejected() throws {
        let stroke = try stroke(points: [(0, 0), (1, 0)])
        XCTAssertNil(tester.nearestStrokeID(to: SIMD3(Float.nan, 0, 0), in: [stroke]))
        XCTAssertNil(tester.distance(from: SIMD3(Float.infinity, 0, 0), to: stroke))
        XCTAssertNil(stroke.translated(by: SIMD3(Float.infinity, 0, 0)))
    }

    func testTranslationPreservesIdentityStyleOrderingAndTimestamps() throws {
        let original = try stroke(points: [(0, 0), (1, 0)])
        let moved = try XCTUnwrap(original.translated(by: SIMD3(0.5, 0.2, -0.1)))

        XCTAssertEqual(moved.id, original.id)
        XCTAssertEqual(moved.style, original.style)
        XCTAssertEqual(moved.createdAt, original.createdAt)
        XCTAssertEqual(moved.points.map(\.timestamp), original.points.map(\.timestamp))
        XCTAssertEqual(moved.points[0].position.simdValue, SIMD3(0.5, 0.2, -0.1))
        XCTAssertEqual(moved.points[1].position.simdValue, SIMD3(1.5, 0.2, -0.1))
    }

    func testBoundsPrefilterContainsGeometryAndRejectsDistantPointWithoutFalseNegative() throws {
        let original = try stroke(points: [(-2, -1), (1, 3), (4, 0)])
        let bounds = try XCTUnwrap(original.spatialBounds)
        XCTAssertEqual(bounds.minimum, SIMD3(-2, -1, 0))
        XCTAssertEqual(bounds.maximum, SIMD3(4, 3, 0))
        XCTAssertEqual(tester.nearestStrokeID(to: SIMD3(1, 3.05, 0), in: [original]), original.id)
        XCTAssertNil(tester.nearestStrokeID(to: SIMD3(10, 10, 0), in: [original]))
    }

    func testDeterministicLargeCanvasBenchmarkFixturesRemainQueryable() throws {
        for strokeCount in [100, 500, 1_000] {
            let strokes = try LargeCanvasBenchmarkFixture.makeCanvas(
                strokeCount: strokeCount,
                pointsPerStroke: 8
            )
            XCTAssertEqual(strokes.count, strokeCount)
            XCTAssertEqual(strokes.reduce(0) { $0 + $1.points.count }, strokeCount * 8)
            XCTAssertNotNil(tester.nearestStrokeID(to: SIMD3(0.03, 0.01, 0), in: strokes))
        }
    }

    private func stroke(id: UUID = UUID(), points: [(Float, Float)]) throws -> Stroke {
        try Stroke(
            id: id,
            points: try points.enumerated().map { index, point in
                try StrokePoint(
                    position: CanvasPoint3D(x: point.0, y: point.1, z: 0),
                    timestamp: TimeInterval(index)
                )
            },
            style: .defaultStyle,
            createdAt: Date(timeIntervalSinceReferenceDate: 1)
        )
    }
}

/// DEBUG-test fixture only. It intentionally produces stable geometry and does
/// not ship as user-visible canvas content.
private enum LargeCanvasBenchmarkFixture {
    static func makeCanvas(strokeCount: Int, pointsPerStroke: Int) throws -> [Stroke] {
        precondition(strokeCount > 0 && pointsPerStroke >= 2)
        return try (0 ..< strokeCount).map { strokeIndex in
            let baseX = Float(strokeIndex % 50) * 0.06
            let baseY = Float(strokeIndex / 50) * 0.06
            return try Stroke(
                id: UUID(),
                points: try (0 ..< pointsPerStroke).map { pointIndex in
                    try StrokePoint(
                        position: CanvasPoint3D(
                            x: baseX + Float(pointIndex) * 0.004,
                            y: baseY,
                            z: -Float(pointIndex) * 0.001
                        ),
                        timestamp: TimeInterval(pointIndex) * 0.01
                    )
                },
                style: .defaultStyle,
                createdAt: Date(timeIntervalSinceReferenceDate: TimeInterval(strokeIndex))
            )
        }
    }
}
