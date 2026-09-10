import Foundation

/// Immutable, ordered geometry and style for one completed drawing stroke.
struct Stroke: Codable, Equatable, Hashable, Sendable, Identifiable {
    let id: UUID
    let points: [StrokePoint]
    let style: BrushStyle
    let createdAt: Date

    init(
        id: UUID = UUID(),
        points: [StrokePoint],
        style: BrushStyle,
        createdAt: Date = .now
    ) throws {
        guard points.count >= 2 else {
            throw StrokeValidationError.insufficientPoints
        }

        self.id = id
        self.points = points
        self.style = style
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(UUID.self, forKey: .id),
            points: container.decode([StrokePoint].self, forKey: .points),
            style: container.decode(BrushStyle.self, forKey: .style),
            createdAt: container.decode(Date.self, forKey: .createdAt)
        )
    }
}

enum StrokeValidationError: Error, Equatable, Sendable {
    case insufficientPoints
}
