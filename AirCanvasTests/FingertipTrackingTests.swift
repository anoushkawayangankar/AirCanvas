import CoreGraphics
import XCTest
@testable import AirCanvas

final class FingertipTrackingTests: XCTestCase {
    func testCenterAndEdgesMapToViewport() {
        let converter = VisionCoordinateConverter()
        XCTAssertEqual(converter.displayPoint(from: CGPoint(x: 0.5, y: 0.5), viewportSize: CGSize(width: 200, height: 400)), CGPoint(x: 100, y: 200))
        XCTAssertEqual(converter.displayPoint(from: CGPoint(x: 0, y: 1), viewportSize: CGSize(width: 200, height: 400)), .zero)
    }
    func testInvalidCoordinatesAreRejected() { XCTAssertNil(VisionCoordinateConverter().displayPoint(from: CGPoint(x: CGFloat.nan, y: 0), viewportSize: CGSize(width: 1, height: 1))) }
    func testSmootherInitializesAndResets() {
        var smoother = PointSmoother(factor: 0.5)
        XCTAssertEqual(smoother.update(CGPoint(x: 1, y: 1)), CGPoint(x: 1, y: 1))
        XCTAssertEqual(smoother.update(CGPoint(x: 3, y: 3)), CGPoint(x: 2, y: 2))
        smoother.reset(); XCTAssertEqual(smoother.update(CGPoint(x: 9, y: 9)), CGPoint(x: 9, y: 9))
    }
    func testWorldProcessorSmoothsAndRejectsLargeJumpUntilReset() {
        var processor = SpatialFingertipProcessor()
        XCTAssertEqual(processor.accept(SIMD3(0, 0, 0)), SIMD3(0, 0, 0))
        XCTAssertNotNil(processor.accept(SIMD3(0.1, 0, 0)))
        XCTAssertNil(processor.accept(SIMD3(2, 0, 0)))
        processor.reset()
        XCTAssertEqual(processor.accept(SIMD3(2, 0, 0)), SIMD3(2, 0, 0))
    }
    func testWorldProcessorRejectsNonFiniteCoordinates() {
        var processor = SpatialFingertipProcessor()
        XCTAssertNil(processor.accept(SIMD3(Float.nan, 0, 0)))
    }
}
