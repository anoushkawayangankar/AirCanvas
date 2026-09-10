import CoreGraphics
import Foundation

enum PinchGestureState: Equatable, Sendable { case idle, pinchCandidate, pinching, releaseCandidate }
enum PinchGestureEvent: Equatable, Sendable { case began, ended, cancelled }
struct PinchGestureConfiguration: Sendable {
    let entryThreshold: CGFloat; let releaseThreshold: CGFloat
    let confirmation: TimeInterval; let releaseConfirmation: TimeInterval; let lossGrace: TimeInterval
    init(entryThreshold: CGFloat = 0.09, releaseThreshold: CGFloat = 0.14, confirmation: TimeInterval = 0.12, releaseConfirmation: TimeInterval = 0.12, lossGrace: TimeInterval = 0.18) {
        precondition(entryThreshold > 0 && releaseThreshold > entryThreshold && confirmation >= 0 && releaseConfirmation >= 0 && lossGrace >= 0)
        self.entryThreshold = entryThreshold; self.releaseThreshold = releaseThreshold; self.confirmation = confirmation; self.releaseConfirmation = releaseConfirmation; self.lossGrace = lossGrace
    }
}
struct PinchGestureClassifier: Sendable {
    private(set) var state: PinchGestureState = .idle
    private var stateSince: TimeInterval = 0
    private var handLossSince: TimeInterval?
    private let configuration: PinchGestureConfiguration
    init(configuration: PinchGestureConfiguration = .init()) { self.configuration = configuration }
    mutating func update(hand: HandTrackingState, timestamp: TimeInterval) -> PinchGestureEvent? {
        guard timestamp.isFinite else { return nil }
        guard case .detected(let pose) = hand else {
            guard state == .pinching || state == .releaseCandidate else {
                state = .idle
                handLossSince = nil
                return nil
            }

            let lossStart = handLossSince ?? timestamp
            handLossSince = lossStart
            guard timestamp - lossStart >= configuration.lossGrace else { return nil }
            state = .idle
            handLossSince = nil
            return .cancelled
        }
        handLossSince = nil
        let dx = pose.indexTip.normalizedPosition.x - pose.thumbTip.normalizedPosition.x
        let dy = pose.indexTip.normalizedPosition.y - pose.thumbTip.normalizedPosition.y
        let distance = hypot(dx, dy)
        guard distance.isFinite else { state = .idle; return nil }
        switch state {
        case .idle where distance < configuration.entryThreshold: state = .pinchCandidate; stateSince = timestamp
        case .pinchCandidate where distance >= configuration.entryThreshold: state = .idle
        case .pinchCandidate where timestamp - stateSince >= configuration.confirmation: state = .pinching; return .began
        case .pinching where distance > configuration.releaseThreshold: state = .releaseCandidate; stateSince = timestamp
        case .releaseCandidate where distance <= configuration.releaseThreshold: state = .pinching
        case .releaseCandidate where timestamp - stateSince >= configuration.releaseConfirmation: state = .idle; return .ended
        default: break
        }; return nil
    }
    mutating func reset() { state = .idle; stateSince = 0; handLossSince = nil }
}
