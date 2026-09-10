import XCTest
@testable import AirCanvas

final class StrokeTransformerTests: XCTestCase {
    func testCentroidAndScalePreserveIdentityStyleAndThickness() throws {
        let stroke = try makeStroke([(0, 0, 0), (2, 0, 0)])
        let transformer = StrokeTransformer()
        XCTAssertEqual(transformer.centroid(of: stroke)?.simdValue, SIMD3<Float>(1, 0, 0))
        let scaled = try XCTUnwrap(transformer.scale(stroke, by: 2))
        XCTAssertEqual(scaled.id, stroke.id)
        XCTAssertEqual(scaled.style, stroke.style)
        XCTAssertEqual(scaled.points.map { $0.position.simdValue }, [SIMD3<Float>(-1, 0, 0), SIMD3<Float>(3, 0, 0)])
    }

    func testRotationUsesWorldUpAxisAndPreservesPivot() throws {
        let stroke = try makeStroke([(0, 0, 0), (2, 0, 0)])
        let rotated = try XCTUnwrap(StrokeTransformer().rotate(stroke, by: .pi / 2))
        XCTAssertEqual(rotated.points[0].position.simdValue.x, 1, accuracy: 0.0001)
        XCTAssertEqual(rotated.points[0].position.simdValue.z, 1, accuracy: 0.0001)
        XCTAssertEqual(rotated.points[1].position.simdValue.x, 1, accuracy: 0.0001)
        XCTAssertEqual(rotated.points[1].position.simdValue.z, -1, accuracy: 0.0001)
    }

    func testInvalidValuesAndScaleLimitsAreSafe() throws {
        let stroke = try makeStroke([(0, 0, 0), (1, 0, 0)])
        let transformer = StrokeTransformer()
        XCTAssertNil(transformer.scale(stroke, by: .nan))
        XCTAssertNil(transformer.rotate(stroke, by: .infinity))
        let minimum = try XCTUnwrap(transformer.scale(stroke, by: 0.01))
        let maximum = try XCTUnwrap(transformer.scale(stroke, by: 99))
        XCTAssertEqual(minimum.points[0].position.simdValue.x, 0.375, accuracy: 0.001)
        XCTAssertEqual(maximum.points[1].position.simdValue.x, 2.5, accuracy: 0.001)
    }

    private func makeStroke(_ values: [(Float, Float, Float)]) throws -> Stroke {
        let points = try values.map { try StrokePoint(position: CanvasPoint3D(x: $0.0, y: $0.1, z: $0.2)) }
        return try Stroke(points: points, style: .defaultStyle)
    }
}
