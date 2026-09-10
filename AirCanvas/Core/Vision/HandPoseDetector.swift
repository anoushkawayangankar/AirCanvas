@preconcurrency import Vision
import CoreVideo
import Foundation
import ImageIO

/// Performs one on-device Vision request. It has no AR, rendering, drawing, or UI responsibility.
final class HandPoseDetector: @unchecked Sendable {
    private let configuration: HandPoseDetectionConfiguration

    init(configuration: HandPoseDetectionConfiguration = .standard) {
        self.configuration = configuration
    }

    func detect(pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) throws -> HandTrackingState {
        let request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = 1
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation)
        try handler.perform([request])
        guard let observation = request.results?.first else { return .noHand }

        let points = try observation.recognizedPoints(.all)
        func landmark(_ joint: VNHumanHandPoseObservation.JointName) -> HandLandmark? {
            guard let point = points[joint] else { return nil }
            return HandLandmark(normalizedPosition: CGPoint(x: point.location.x, y: point.location.y), confidence: point.confidence)
        }

        return HandPoseResultMapper.state(
            indexTip: landmark(.indexTip),
            thumbTip: landmark(.thumbTip),
            wrist: landmark(.wrist),
            minimumConfidence: configuration.minimumConfidence
        )
    }
}
