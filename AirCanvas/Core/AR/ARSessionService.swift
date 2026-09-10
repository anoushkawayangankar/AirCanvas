@preconcurrency import ARKit
import Foundation
import ImageIO

@MainActor
protocol ARSessionControlling: AnyObject {
    func setEventHandler(_ handler: @escaping @MainActor (ARSessionEvent) -> Void)
    func start()
    func pause()
    func restart()
    func start(relocalizingWith initialWorldMap: ARWorldMap)
    func requestWorldMap() async throws -> ARWorldMap
    func setCameraFrameHandler(_ handler: @escaping @Sendable (ARCameraFrame) -> Void)
}

/// Transient AR camera data forwarded to Vision only; it is never persisted or exposed to UI.
struct ARCameraFrame: @unchecked Sendable {
    let pixelBuffer: CVPixelBuffer
    let timestamp: TimeInterval
    let orientation: CGImagePropertyOrientation
}

@MainActor
final class ARSessionService: NSObject, ARSessionControlling {
    let session: ARSession
    nonisolated private let cameraFrameForwarder = ARCameraFrameForwarder()
    nonisolated private let mappingQualityForwarder = ARMappingQualityForwarder()

    private var eventHandler: (@MainActor (ARSessionEvent) -> Void)?
    private var isRunning = false
    private var initialWorldMap: ARWorldMap?

    init(initialWorldMap: ARWorldMap? = nil) {
        session = ARSession()
        self.initialWorldMap = initialWorldMap
        super.init()
        session.delegate = self
    }

    deinit {
        session.pause()
        session.delegate = nil
    }

    func setEventHandler(_ handler: @escaping @MainActor (ARSessionEvent) -> Void) {
        eventHandler = handler
    }

    func start() {
        guard !isRunning else {
            return
        }

        runSession(options: [], initialWorldMap: initialWorldMap)
        publish(.started)
        AppLogger.ar.info("AR session started")
    }

    func pause() {
        guard isRunning else {
            return
        }

        session.pause()
        isRunning = false
        publish(.paused)
        AppLogger.ar.info("AR session paused")
    }

    func restart() {
        initialWorldMap = nil
        runSession(options: [.resetTracking, .removeExistingAnchors])
        publish(.started)
        AppLogger.ar.info("AR session restarted")
    }

    func start(relocalizingWith initialWorldMap: ARWorldMap) {
        guard !isRunning else { return }
        self.initialWorldMap = initialWorldMap
        runSession(options: [], initialWorldMap: initialWorldMap)
        publish(.started)
        AppLogger.ar.info("AR session started for relocalization")
    }

    func requestWorldMap() async throws -> ARWorldMap {
        guard isRunning else { throw SpatialWorldMapError.unavailable }
        return try await withCheckedThrowingContinuation { continuation in
            session.getCurrentWorldMap { worldMap, error in
                if let worldMap {
                    continuation.resume(returning: worldMap)
                } else {
                    continuation.resume(throwing: error ?? SpatialWorldMapError.unavailable)
                }
            }
        }
    }

    func setCameraFrameHandler(_ handler: @escaping @Sendable (ARCameraFrame) -> Void) {
        cameraFrameForwarder.setHandler(handler)
    }

    private func runSession(options: ARSession.RunOptions, initialWorldMap: ARWorldMap? = nil) {
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.initialWorldMap = initialWorldMap
        session.run(configuration, options: options)
        isRunning = true
    }

    private func publish(_ event: ARSessionEvent) {
        eventHandler?(event)
    }
}

extension ARSessionService: ARSessionDelegate {
    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let cameraFrame = ARCameraFrame(
            pixelBuffer: frame.capturedImage,
            timestamp: frame.timestamp,
            // ARKit's rear-camera buffer is landscape; `.right` maps it to the supported portrait Canvas orientation.
            orientation: .right
        )
        cameraFrameForwarder.forward(cameraFrame)
        let quality = SpatialWorldMapCoder.mappingQuality(from: frame.worldMappingStatus)
        if mappingQualityForwarder.shouldForward(quality) {
            Task { @MainActor [weak self] in self?.publish(.mappingQualityChanged(quality)) }
        }
    }
    nonisolated func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        let trackingState = ARTrackingState(cameraTrackingState: camera.trackingState)
        Task { @MainActor [weak self] in
            self?.handleTrackingStateChange(trackingState)
        }
    }

    nonisolated func sessionWasInterrupted(_ session: ARSession) {
        Task { @MainActor [weak self] in
            self?.handleInterruptionBegan()
        }
    }

    nonisolated func sessionInterruptionEnded(_ session: ARSession) {
        Task { @MainActor [weak self] in
            self?.handleInterruptionEnded()
        }
    }

    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        let description = error.localizedDescription
        Task { @MainActor [weak self] in
            self?.handleFailure(description: description)
        }
    }
}

/// Thread-safe forwarding avoids scheduling one MainActor task for every AR
/// camera frame. The sole consumer is the bounded hand-tracking coordinator.
private final class ARCameraFrameForwarder: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable (ARCameraFrame) -> Void)?

    func setHandler(_ handler: @escaping @Sendable (ARCameraFrame) -> Void) {
        lock.lock(); defer { lock.unlock() }
        self.handler = handler
    }

    func forward(_ frame: ARCameraFrame) {
        lock.lock()
        let handler = handler
        lock.unlock()
        handler?(frame)
    }
}

private final class ARMappingQualityForwarder: @unchecked Sendable {
    private let lock = NSLock()
    private var lastForwardedQuality: SpatialMappingQuality?

    func shouldForward(_ quality: SpatialMappingQuality) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard lastForwardedQuality != quality else { return false }
        lastForwardedQuality = quality
        return true
    }
}

private extension ARSessionService {
    func handleTrackingStateChange(_ trackingState: ARTrackingState) {
        publish(.trackingChanged(trackingState))

        if trackingState != .normal {
            AppLogger.ar.debug("AR tracking state changed: \(String(describing: trackingState), privacy: .public)")
        }
    }

    func handleInterruptionBegan() {
        publish(.interrupted)
        AppLogger.ar.notice("AR session interruption began")
    }

    func handleInterruptionEnded() {
        guard isRunning else {
            return
        }

        runSession(options: [.resetTracking, .removeExistingAnchors])
        publish(.interruptionEnded)
        AppLogger.ar.notice("AR session interruption ended and was restarted")
    }

    func handleFailure(description: String) {
        isRunning = false
        publish(.failed(.sessionFailed))
        AppLogger.ar.error("AR session failed: \(description, privacy: .private(mask: .hash))")
    }
}
