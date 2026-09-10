import CoreGraphics
import XCTest
@testable import AirCanvas

final class HandTrackingTests: XCTestCase {
    func testHighConfidenceRequiredLandmarksProduceDetectedState() {
        let state = HandPoseResultMapper.state(
            indexTip: landmark(confidence: 0.9), thumbTip: landmark(confidence: 0.8), wrist: landmark(confidence: 0.7), minimumConfidence: 0.65
        )
        guard case .detected = state else { return XCTFail("Expected a detected hand") }
    }

    func testLowConfidenceRequiredLandmarkIsUnreliable() {
        XCTAssertEqual(
            HandPoseResultMapper.state(indexTip: landmark(confidence: 0.5), thumbTip: landmark(confidence: 0.9), wrist: nil, minimumConfidence: 0.65),
            .unreliable
        )
    }

    func testMissingRequiredLandmarkIsNoHand() {
        XCTAssertEqual(HandPoseResultMapper.state(indexTip: nil, thumbTip: landmark(confidence: 0.9), wrist: nil, minimumConfidence: 0.65), .noHand)
    }

    func testInvalidNormalizedCoordinateIsRejected() {
        XCTAssertNil(HandLandmark(normalizedPosition: CGPoint(x: 1.1, y: 0.5), confidence: 0.9))
    }

    func testGateThrottlesAndRecoversAfterCompletion() {
        var gate = HandFrameProcessingGate()
        XCTAssertTrue(gate.acceptFrame(timestamp: 0, maximumRate: 15))
        XCTAssertFalse(gate.acceptFrame(timestamp: 1, maximumRate: 15))
        gate.completeRequest()
        XCTAssertFalse(gate.acceptFrame(timestamp: 0.01, maximumRate: 15))
        XCTAssertTrue(gate.acceptFrame(timestamp: 0.07, maximumRate: 15))
    }

    func testStoppingGateClearsBusyStateAndTimestamp() {
        var gate = HandFrameProcessingGate()
        XCTAssertTrue(gate.acceptFrame(timestamp: 2, maximumRate: 15))
        gate.stop()
        XCTAssertTrue(gate.acceptFrame(timestamp: 0, maximumRate: 15))
    }

    func testVisionSchedulerBoundsWorkToOneInFlightAndOneLatestPendingFrame() {
        var scheduler = VisionFrameScheduler()
        XCTAssertEqual(scheduler.submit(timestamp: 0, maximumRate: 15), .start)
        XCTAssertEqual(scheduler.submit(timestamp: 0.01, maximumRate: 15), .queuedLatest)
        XCTAssertEqual(scheduler.submit(timestamp: 0.02, maximumRate: 15), .queuedLatest)
        XCTAssertTrue(scheduler.isProcessing)
        XCTAssertTrue(scheduler.hasPendingFrame)

        XCTAssertTrue(scheduler.completeRequest(nextTimestamp: 0.02))
        XCTAssertTrue(scheduler.isProcessing)
        XCTAssertFalse(scheduler.hasPendingFrame)
        XCTAssertEqual(scheduler.lastStartedTimestamp, 0.02)
        XCTAssertFalse(scheduler.completeRequest(nextTimestamp: nil))
        XCTAssertFalse(scheduler.isProcessing)
    }

    func testVisionSchedulerStopsAndDropsInvalidOrTooFrequentFrames() {
        var scheduler = VisionFrameScheduler()
        XCTAssertEqual(scheduler.submit(timestamp: .nan, maximumRate: 15), .droppedForCadence)
        XCTAssertEqual(scheduler.submit(timestamp: 0, maximumRate: 15), .start)
        XCTAssertFalse(scheduler.completeRequest(nextTimestamp: nil))
        XCTAssertEqual(scheduler.submit(timestamp: 0.01, maximumRate: 15), .droppedForCadence)
        scheduler.stop()
        XCTAssertEqual(scheduler.submit(timestamp: 0, maximumRate: 15), .start)
    }

    func testThermalAndLowPowerPolicyUsesBoundedDeterministicCadence() {
        let nominal = HandTrackingPerformancePolicy.resolve(
            thermalState: .nominal,
            isLowPowerModeEnabled: false
        )
        let fair = HandTrackingPerformancePolicy.resolve(
            thermalState: .fair,
            isLowPowerModeEnabled: false
        )
        let serious = HandTrackingPerformancePolicy.resolve(
            thermalState: .serious,
            isLowPowerModeEnabled: false
        )
        let critical = HandTrackingPerformancePolicy.resolve(
            thermalState: .critical,
            isLowPowerModeEnabled: false
        )
        let lowPower = HandTrackingPerformancePolicy.resolve(
            thermalState: .nominal,
            isLowPowerModeEnabled: true
        )

        XCTAssertEqual(nominal.maximumAnalysisRate, 15)
        XCTAssertEqual(fair.maximumAnalysisRate, nominal.maximumAnalysisRate)
        XCTAssertEqual(serious.maximumAnalysisRate, 12)
        XCTAssertEqual(critical.maximumAnalysisRate, 8)
        XCTAssertEqual(lowPower.maximumAnalysisRate, 12)
        XCTAssertFalse(nominal.showsReducedPerformanceHint)
        XCTAssertTrue(serious.showsReducedPerformanceHint)
        XCTAssertTrue(critical.showsReducedPerformanceHint)
    }

    private func landmark(confidence: Float) -> HandLandmark {
        HandLandmark(normalizedPosition: CGPoint(x: 0.5, y: 0.5), confidence: confidence)!
    }
}
