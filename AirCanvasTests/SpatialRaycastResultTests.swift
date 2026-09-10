import simd
import XCTest
@testable import AirCanvas

final class SpatialRaycastResultTests: XCTestCase {
    func testResultExtractsWorldPositionFromTransform() {
        var transform = matrix_identity_float4x4
        transform.columns.3 = SIMD4(1.25, -0.5, 3.75, 1)

        let result = SpatialRaycastResult(
            worldTransform: transform,
            source: .existingPlaneGeometry
        )

        XCTAssertEqual(result.worldPosition, SIMD3(1.25, -0.5, 3.75))
        XCTAssertEqual(result.source, .existingPlaneGeometry)
    }

    func testOnlyNormalTrackingIsEligibleForRaycasting() {
        XCTAssertEqual(SpatialRaycastReadiness(trackingState: .normal), .ready)

        XCTAssertEqual(
            SpatialRaycastReadiness(trackingState: .limited(.excessiveMotion)),
            .unavailable(guidance: "Move your device more slowly.")
        )
        XCTAssertEqual(
            SpatialRaycastReadiness(trackingState: .unavailable),
            .unavailable(guidance: "Spatial tracking is temporarily unavailable.")
        )
    }
}
