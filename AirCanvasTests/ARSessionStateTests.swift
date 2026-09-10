import ARKit
import XCTest
@testable import AirCanvas

final class ARSessionStateTests: XCTestCase {
    func testLimitedTrackingReasonsMapToUsefulGuidance() {
        XCTAssertEqual(
            ARTrackingLimitation(reason: .excessiveMotion).guidance,
            "Move your device more slowly."
        )
        XCTAssertEqual(
            ARTrackingLimitation(reason: .insufficientFeatures).guidance,
            "Point toward a well-lit, textured area."
        )
        XCTAssertEqual(
            ARTrackingLimitation(reason: .relocalizing).guidance,
            "Relocalizing your space. Move slowly and look around."
        )
    }

    func testReducerRepresentsInterruptionAndFailure() {
        let interrupted = ARSessionStateReducer.state(after: .interrupted, from: .running(.normal))
        let failed = ARSessionStateReducer.state(after: .failed(.sessionFailed), from: interrupted)

        XCTAssertEqual(interrupted, .interrupted)
        XCTAssertEqual(failed, .failed(.sessionFailed))
    }

    func testReducerReturnsToInitializingAfterAnInterruptionEnds() {
        let state = ARSessionStateReducer.state(after: .interruptionEnded, from: .interrupted)

        XCTAssertEqual(state, .running(.initializing))
    }
}
