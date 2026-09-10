import CoreGraphics
import Foundation

struct HandLandmark: Equatable, Sendable {
    let normalizedPosition: CGPoint
    let confidence: Float

    init?(normalizedPosition: CGPoint, confidence: Float) {
        guard normalizedPosition.x.isFinite, normalizedPosition.y.isFinite,
              (0 ... 1).contains(normalizedPosition.x), (0 ... 1).contains(normalizedPosition.y),
              confidence.isFinite, (0 ... 1).contains(confidence) else { return nil }
        self.normalizedPosition = normalizedPosition
        self.confidence = confidence
    }
}

struct HandPose: Equatable, Sendable {
    let indexTip: HandLandmark
    let thumbTip: HandLandmark
    let wrist: HandLandmark?
}

enum HandTrackingState: Equatable, Sendable {
    case noHand
    case unreliable
    case detected(HandPose)

    var statusText: String {
        switch self {
        case .noHand: "No hand detected"
        case .unreliable: "Hand detection is limited"
        case .detected: "Hand detected"
        }
    }
}

struct HandPoseDetectionConfiguration: Equatable, Sendable {
    let minimumConfidence: Float
    let maximumAnalysisRate: Double

    static let standard = Self(minimumConfidence: 0.65, maximumAnalysisRate: 15)
}

/// Centralizes the conservative runtime cadence used by the bounded Vision
/// scheduler. ARKit can continue at its own cadence; only Vision is adapted.
struct HandTrackingPerformancePolicy: Equatable, Sendable {
    let maximumAnalysisRate: Double
    let showsReducedPerformanceHint: Bool

    static func resolve(
        baseMaximumRate: Double = HandPoseDetectionConfiguration.standard.maximumAnalysisRate,
        thermalState: ProcessInfo.ThermalState,
        isLowPowerModeEnabled: Bool
    ) -> Self {
        let thermalRate: Double
        switch thermalState {
        case .nominal, .fair:
            thermalRate = baseMaximumRate
        case .serious:
            thermalRate = min(baseMaximumRate, 12)
        case .critical:
            thermalRate = min(baseMaximumRate, 8)
        @unknown default:
            thermalRate = min(baseMaximumRate, 12)
        }
        let rate = isLowPowerModeEnabled ? min(thermalRate, 12) : thermalRate
        return Self(maximumAnalysisRate: max(rate, 1), showsReducedPerformanceHint: rate < baseMaximumRate)
    }
}

enum VisionFrameSchedulingDecision: Equatable, Sendable {
    case start
    case queuedLatest
    case droppedForCadence
}

/// Pure one-in-flight/one-pending scheduler. The coordinator owns the actual
/// pixel buffer, while this value keeps the decision state deterministic and
/// testable without Vision or ARKit.
struct VisionFrameScheduler: Equatable, Sendable {
    private(set) var isProcessing = false
    private(set) var hasPendingFrame = false
    private(set) var lastStartedTimestamp: TimeInterval?

    mutating func submit(timestamp: TimeInterval, maximumRate: Double) -> VisionFrameSchedulingDecision {
        guard timestamp.isFinite, maximumRate.isFinite, maximumRate > 0 else {
            return .droppedForCadence
        }
        if isProcessing {
            hasPendingFrame = true
            return .queuedLatest
        }
        let minimumInterval = 1 / maximumRate
        guard lastStartedTimestamp.map({ timestamp - $0 >= minimumInterval }) ?? true else {
            return .droppedForCadence
        }
        isProcessing = true
        lastStartedTimestamp = timestamp
        return .start
    }

    mutating func completeRequest(nextTimestamp: TimeInterval?) -> Bool {
        isProcessing = false
        guard hasPendingFrame, let nextTimestamp, nextTimestamp.isFinite else {
            hasPendingFrame = false
            return false
        }
        hasPendingFrame = false
        isProcessing = true
        lastStartedTimestamp = nextTimestamp
        return true
    }

    mutating func stop() {
        isProcessing = false
        hasPendingFrame = false
        lastStartedTimestamp = nil
    }
}

enum HandPoseResultMapper {
    static func state(
        indexTip: HandLandmark?,
        thumbTip: HandLandmark?,
        wrist: HandLandmark?,
        minimumConfidence: Float
    ) -> HandTrackingState {
        guard let indexTip, let thumbTip else { return .noHand }
        guard indexTip.confidence >= minimumConfidence, thumbTip.confidence >= minimumConfidence else {
            return .unreliable
        }
        return .detected(HandPose(indexTip: indexTip, thumbTip: thumbTip, wrist: wrist))
    }
}

/// Pure throttle decision state. A busy analysis drops newly arriving frames rather than queuing stale work.
struct HandFrameProcessingGate: Equatable, Sendable {
    private(set) var isProcessing = false
    private(set) var lastAcceptedTimestamp: TimeInterval?

    mutating func acceptFrame(timestamp: TimeInterval, maximumRate: Double) -> Bool {
        guard !isProcessing, timestamp.isFinite, maximumRate > 0 else { return false }
        let minimumInterval = 1 / maximumRate
        guard lastAcceptedTimestamp.map({ timestamp - $0 >= minimumInterval }) ?? true else { return false }
        isProcessing = true
        lastAcceptedTimestamp = timestamp
        return true
    }

    mutating func completeRequest() { isProcessing = false }
    mutating func stop() { isProcessing = false; lastAcceptedTimestamp = nil }
}
