import Foundation

/// One ordered sample belonging to a completed spatial stroke.
struct StrokePoint: Codable, Equatable, Hashable, Sendable {
    let position: CanvasPoint3D
    /// Relative input time in seconds, when an input source provides it.
    let timestamp: TimeInterval?

    init(position: CanvasPoint3D, timestamp: TimeInterval? = nil) throws {
        guard timestamp?.isFinite ?? true else {
            throw StrokePointValidationError.nonFiniteTimestamp
        }

        self.position = position
        self.timestamp = timestamp
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            position: container.decode(CanvasPoint3D.self, forKey: .position),
            timestamp: container.decodeIfPresent(TimeInterval.self, forKey: .timestamp)
        )
    }
}

enum StrokePointValidationError: Error, Equatable, Sendable {
    case nonFiniteTimestamp
}
