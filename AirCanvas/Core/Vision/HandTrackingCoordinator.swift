import CoreVideo
import Foundation
import ImageIO
import OSLog

struct HandTrackingDiagnostics: Equatable, Sendable {
    let submittedFrames: Int
    let startedRequests: Int
    let queuedLatestFrames: Int
    let droppedForCadence: Int
    let publishedResults: Int
    let averageRequestDuration: TimeInterval
}

/// Serial, bounded AR-frame consumer. It retains at most one latest pending
/// pixel buffer, avoiding an unbounded camera-frame backlog while preserving
/// responsive hand state after a slower Vision request.
final class HandTrackingCoordinator: @unchecked Sendable {
    private let detector: HandPoseDetector
    private let configuration: HandPoseDetectionConfiguration
    private let queue = DispatchQueue(label: "com.aircanvas.hand-pose", qos: .userInitiated)
    private let lock = NSLock()
    private var scheduler = VisionFrameScheduler()
    private var pendingFrame: QueuedVisionFrame?
    private var isEnabled = false
    private var generation = 0
    private var nextSequence = 0
    private var lastPublishedSequence = 0
    private var policy: HandTrackingPerformancePolicy
    private var submittedFrames = 0
    private var startedRequests = 0
    private var queuedLatestFrames = 0
    private var droppedForCadence = 0
    private var publishedResults = 0
    private var cumulativeRequestDuration: TimeInterval = 0
    private var stateHandler: (@MainActor (HandTrackingState) -> Void)?
    private var notificationObservers: [NSObjectProtocol] = []
#if DEBUG
    private let signposter = OSSignposter(
        subsystem: Bundle.main.bundleIdentifier ?? "com.aircanvas.app",
        category: "vision"
    )
#endif

    init(
        detector: HandPoseDetector = HandPoseDetector(),
        configuration: HandPoseDetectionConfiguration = .standard
    ) {
        self.detector = detector
        self.configuration = configuration
        policy = .resolve(
            baseMaximumRate: configuration.maximumAnalysisRate,
            thermalState: ProcessInfo.processInfo.thermalState,
            isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
        let notificationCenter = NotificationCenter.default
        notificationObservers = [
            notificationCenter.addObserver(
                forName: ProcessInfo.thermalStateDidChangeNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in self?.refreshPerformancePolicy() },
            notificationCenter.addObserver(
                forName: .NSProcessInfoPowerStateDidChange,
                object: nil,
                queue: nil
            ) { [weak self] _ in self?.refreshPerformancePolicy() }
        ]
    }

    deinit {
        notificationObservers.forEach(NotificationCenter.default.removeObserver)
    }

    func setStateHandler(_ handler: @escaping @MainActor (HandTrackingState) -> Void) {
        lock.lock(); defer { lock.unlock() }
        stateHandler = handler
    }

    func setEnabled(_ enabled: Bool) {
        lock.lock(); defer { lock.unlock() }
        guard isEnabled != enabled else { return }
        isEnabled = enabled
        generation &+= 1
        if !enabled {
            scheduler.stop()
            pendingFrame = nil
        }
    }

    func submit(pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation, timestamp: TimeInterval) {
        lock.lock()
        submittedFrames += 1
        guard isEnabled else {
            lock.unlock()
            return
        }
        let decision = scheduler.submit(timestamp: timestamp, maximumRate: policy.maximumAnalysisRate)
        let acceptedGeneration = generation
        nextSequence &+= 1
        let sequence = nextSequence
        let frame = QueuedVisionFrame(
            input: VisionFrameInput(pixelBuffer: pixelBuffer, orientation: orientation),
            timestamp: timestamp,
            generation: acceptedGeneration,
            sequence: sequence
        )
        switch decision {
        case .start:
            startedRequests += 1
        case .queuedLatest:
            pendingFrame = frame
            queuedLatestFrames += 1
        case .droppedForCadence:
            droppedForCadence += 1
        }
        lock.unlock()
        guard case .start = decision else { return }
        enqueue(frame)
    }

    func diagnostics() -> HandTrackingDiagnostics {
        lock.lock(); defer { lock.unlock() }
        return HandTrackingDiagnostics(
            submittedFrames: submittedFrames,
            startedRequests: startedRequests,
            queuedLatestFrames: queuedLatestFrames,
            droppedForCadence: droppedForCadence,
            publishedResults: publishedResults,
            averageRequestDuration: startedRequests > 0 ? cumulativeRequestDuration / Double(startedRequests) : 0
        )
    }

    private func enqueue(_ frame: QueuedVisionFrame) {
        queue.async { [weak self] in self?.process(frame) }
    }

    private func process(_ frame: QueuedVisionFrame) {
#if DEBUG
        let signpostState = signposter.beginInterval("VisionRequest")
#endif
        let start = ProcessInfo.processInfo.systemUptime
        let state: HandTrackingState
        do {
            state = try detector.detect(pixelBuffer: frame.input.pixelBuffer, orientation: frame.input.orientation)
        } catch {
            AppLogger.vision.error("Hand-pose request failed: \(error.localizedDescription, privacy: .private(mask: .hash))")
            state = .unreliable
        }
        let duration = max(ProcessInfo.processInfo.systemUptime - start, 0)
#if DEBUG
        signposter.endInterval("VisionRequest", signpostState)
#endif

        lock.lock()
        cumulativeRequestDuration += duration
        let next = pendingFrame
        let startsPending = scheduler.completeRequest(nextTimestamp: next?.timestamp)
        if startsPending {
            pendingFrame = nil
            startedRequests += 1
        }
        let enabled = isEnabled && generation == frame.generation && frame.sequence > lastPublishedSequence
        if enabled {
            lastPublishedSequence = frame.sequence
            publishedResults += 1
        }
        lock.unlock()

        if enabled {
            Task { @MainActor [weak self] in self?.deliver(state, for: frame) }
        }
        if startsPending, let next {
            enqueue(next)
        }
    }

    private func refreshPerformancePolicy() {
        let updated = HandTrackingPerformancePolicy.resolve(
            baseMaximumRate: configuration.maximumAnalysisRate,
            thermalState: ProcessInfo.processInfo.thermalState,
            isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
        lock.lock()
        let changed = policy != updated
        policy = updated
        lock.unlock()
        guard changed else { return }
        AppLogger.performance.notice("Hand tracking performance policy updated")
    }

    @MainActor
    private func deliver(_ state: HandTrackingState, for frame: QueuedVisionFrame) {
        lock.lock()
        let isCurrent = isEnabled && generation == frame.generation && lastPublishedSequence == frame.sequence
        let handler = stateHandler
        lock.unlock()
        guard isCurrent else { return }
        handler?(state)
    }
}

private struct VisionFrameInput: @unchecked Sendable {
    let pixelBuffer: CVPixelBuffer
    let orientation: CGImagePropertyOrientation
}

private struct QueuedVisionFrame: @unchecked Sendable {
    let input: VisionFrameInput
    let timestamp: TimeInterval
    let generation: Int
    let sequence: Int
}
