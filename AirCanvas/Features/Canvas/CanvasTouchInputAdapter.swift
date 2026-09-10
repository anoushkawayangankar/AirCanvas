import CoreGraphics
import Foundation
import RealityKit
import UIKit

@MainActor
protocol CanvasTouchInputHandling: AnyObject {
    var canvasTool: CanvasTool { get }
    func touchDidBegin(at screenPoint: CGPoint, timestamp: TimeInterval)
    func touchDidMove(at screenPoint: CGPoint, timestamp: TimeInterval)
    func touchDidEnd(at screenPoint: CGPoint, timestamp: TimeInterval)
    func touchDidCancel()
    func selectionDidRequest(at screenPoint: CGPoint)
    func touchSelectionDragBegan(at screenPoint: CGPoint)
    func touchSelectionDragMoved(at screenPoint: CGPoint)
    func touchSelectionDragEnded(at screenPoint: CGPoint)
    func touchSelectionDragCancelled()
}

@MainActor
final class CanvasTouchInputAdapter: NSObject {
    private weak var handler: (any CanvasTouchInputHandling)?
    private var panGestureRecognizer: UIPanGestureRecognizer?
    private var tapGestureRecognizer: UITapGestureRecognizer?

    init(handler: any CanvasTouchInputHandling) {
        self.handler = handler
    }

    func install(on arView: ARView) {
        guard panGestureRecognizer == nil, tapGestureRecognizer == nil else {
            return
        }

        let recognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        recognizer.minimumNumberOfTouches = 1
        recognizer.maximumNumberOfTouches = 1
        recognizer.cancelsTouchesInView = false
        arView.addGestureRecognizer(recognizer)
        panGestureRecognizer = recognizer

        let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tapRecognizer.numberOfTapsRequired = 1
        tapRecognizer.numberOfTouchesRequired = 1
        tapRecognizer.cancelsTouchesInView = false
        tapRecognizer.require(toFail: recognizer)
        arView.addGestureRecognizer(tapRecognizer)
        tapGestureRecognizer = tapRecognizer
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        guard let handler, let view = recognizer.view else {
            return
        }

        let point = recognizer.location(in: view)
        let timestamp = ProcessInfo.processInfo.systemUptime

        if handler.canvasTool == .select {
            switch recognizer.state {
            case .began: handler.touchSelectionDragBegan(at: point)
            case .changed: handler.touchSelectionDragMoved(at: point)
            case .ended: handler.touchSelectionDragEnded(at: point)
            case .cancelled, .failed: handler.touchSelectionDragCancelled()
            case .possible: break
            @unknown default: handler.touchSelectionDragCancelled()
            }
            return
        }

        guard handler.canvasTool == .draw else { return }

        switch recognizer.state {
        case .began:
            handler.touchDidBegin(at: point, timestamp: timestamp)
        case .changed:
            handler.touchDidMove(at: point, timestamp: timestamp)
        case .ended:
            handler.touchDidEnd(at: point, timestamp: timestamp)
        case .cancelled, .failed:
            handler.touchDidCancel()
        case .possible:
            break
        @unknown default:
            handler.touchDidCancel()
        }
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard handler?.canvasTool == .select, let view = recognizer.view else {
            return
        }
        handler?.selectionDidRequest(at: recognizer.location(in: view))
    }
}
