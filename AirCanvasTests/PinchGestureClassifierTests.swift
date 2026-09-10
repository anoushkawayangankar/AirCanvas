import CoreGraphics
import XCTest
@testable import AirCanvas

final class PinchGestureClassifierTests: XCTestCase {
    func testSustainedPinchBeginsOnceAndReleaseEndsOnce() {
        var classifier = PinchGestureClassifier()
        XCTAssertEqual(classifier.state, .idle)
        XCTAssertNil(classifier.update(hand: hand(distance: 0.08), timestamp: 0))
        XCTAssertEqual(classifier.state, .pinchCandidate)
        XCTAssertEqual(classifier.update(hand: hand(distance: 0.08), timestamp: 0.13), .began)
        XCTAssertEqual(classifier.update(hand: hand(distance: 0.1), timestamp: 0.2), nil)
        XCTAssertEqual(classifier.update(hand: hand(distance: 0.15), timestamp: 0.3), nil)
        XCTAssertEqual(classifier.update(hand: hand(distance: 0.15), timestamp: 0.43), .ended)
        XCTAssertNil(classifier.update(hand: hand(distance: 0.2), timestamp: 0.6))
    }
    func testCandidateCancelsAndLossCancelsActivePinch() {
        var classifier = PinchGestureClassifier()
        _ = classifier.update(hand: hand(distance: 0.08), timestamp: 0)
        _ = classifier.update(hand: .noHand, timestamp: 0.01)
        XCTAssertEqual(classifier.state, .idle)
        _ = classifier.update(hand: hand(distance: 0.08), timestamp: 1)
        XCTAssertEqual(classifier.update(hand: hand(distance: 0.08), timestamp: 1.13), .began)
        XCTAssertNil(classifier.update(hand: .noHand, timestamp: 1.2))
        XCTAssertEqual(classifier.update(hand: .noHand, timestamp: 1.4), .cancelled)
    }
    func testInvalidAndUnreliableHandCannotPinch() {
        var classifier = PinchGestureClassifier()
        XCTAssertNil(classifier.update(hand: .unreliable, timestamp: 0))
        XCTAssertEqual(classifier.state, .idle)
        classifier.reset(); XCTAssertEqual(classifier.state, .idle)
    }

    func testBriefHandLossAfterLongPinchStillUsesLossGracePeriod() {
        var classifier = PinchGestureClassifier()
        _ = classifier.update(hand: hand(distance: 0.08), timestamp: 0)
        XCTAssertEqual(classifier.update(hand: hand(distance: 0.08), timestamp: 0.13), .began)
        XCTAssertNil(classifier.update(hand: hand(distance: 0.08), timestamp: 10))

        XCTAssertNil(classifier.update(hand: .noHand, timestamp: 10.01))
        XCTAssertEqual(classifier.state, .pinching)
        XCTAssertNil(classifier.update(hand: hand(distance: 0.08), timestamp: 10.05))
        XCTAssertEqual(classifier.state, .pinching)
    }
    private func hand(distance: CGFloat) -> HandTrackingState {
        let index = HandLandmark(normalizedPosition: CGPoint(x: 0.5, y: 0.5), confidence: 1)!
        let thumb = HandLandmark(normalizedPosition: CGPoint(x: 0.5 + distance, y: 0.5), confidence: 1)!
        return .detected(HandPose(indexTip: index, thumbTip: thumb, wrist: nil))
    }
}
