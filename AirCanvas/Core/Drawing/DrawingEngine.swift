import Foundation
import simd

struct DrawingEngineConfiguration: Equatable, Sendable {
    static let standard = DrawingEngineConfiguration(
        minimumPointSpacing: 0.01,
        maximumPointCount: 512
    )

    let minimumPointSpacing: Float
    let maximumPointCount: Int

    init(minimumPointSpacing: Float, maximumPointCount: Int) {
        self.minimumPointSpacing = minimumPointSpacing
        self.maximumPointCount = maximumPointCount
    }

    func isValid() -> Bool {
        minimumPointSpacing.isFinite && minimumPointSpacing > 0 && maximumPointCount >= 2
    }
}

enum DrawingEngineBeginResult: Equatable, Sendable {
    case started(id: UUID, firstPoint: StrokePoint, style: BrushStyle)
    case alreadyDrawing
    case rejectedInvalidTimestamp
}

enum DrawingEngineAppendResult: Equatable, Sendable {
    case appended(id: UUID, previousPoint: StrokePoint, point: StrokePoint, style: BrushStyle)
    case ignoredTooClose
    case ignoredAtCapacity
    case noActiveStroke
    case rejectedInvalidTimestamp
}

enum DrawingEngineEndResult: Equatable, Sendable {
    case completed(Stroke)
    case discarded(id: UUID)
    case noActiveStroke
}

/// Framework-independent state and sampling rules shared by future touch and hand inputs.
final class DrawingEngine {
    private struct ActiveStroke {
        let id: UUID
        let style: BrushStyle
        let createdAt: Date
        let startTimestamp: TimeInterval
        var points: [StrokePoint]
    }

    private let configuration: DrawingEngineConfiguration
    private var activeStroke: ActiveStroke?

    private(set) var completedStrokes: [Stroke] = []

    var isDrawing: Bool {
        activeStroke != nil
    }

    var activeStrokeID: UUID? {
        activeStroke?.id
    }

    init(
        configuration: DrawingEngineConfiguration = .standard,
        completedStrokes: [Stroke] = []
    ) {
        precondition(configuration.isValid(), "DrawingEngineConfiguration must be valid.")
        precondition(
            Set(completedStrokes.map(\.id)).count == completedStrokes.count,
            "DrawingEngine completed strokes must have unique identifiers."
        )
        self.configuration = configuration
        self.completedStrokes = completedStrokes
    }

    func beginStroke(
        at position: CanvasPoint3D,
        style: BrushStyle,
        timestamp: TimeInterval,
        createdAt: Date = .now
    ) -> DrawingEngineBeginResult {
        guard activeStroke == nil else {
            return .alreadyDrawing
        }
        guard timestamp.isFinite else {
            return .rejectedInvalidTimestamp
        }

        guard let firstPoint = try? StrokePoint(position: position, timestamp: 0) else {
            return .rejectedInvalidTimestamp
        }

        let id = UUID()
        activeStroke = ActiveStroke(
            id: id,
            style: style,
            createdAt: createdAt,
            startTimestamp: timestamp,
            points: [firstPoint]
        )
        return .started(id: id, firstPoint: firstPoint, style: style)
    }

    func appendPoint(
        at position: CanvasPoint3D,
        timestamp: TimeInterval
    ) -> DrawingEngineAppendResult {
        guard var activeStroke else {
            return .noActiveStroke
        }
        guard timestamp.isFinite else {
            return .rejectedInvalidTimestamp
        }
        guard activeStroke.points.count < configuration.maximumPointCount else {
            return .ignoredAtCapacity
        }
        guard let previousPoint = activeStroke.points.last else {
            return .noActiveStroke
        }

        let distance = simd_distance(previousPoint.position.simdValue, position.simdValue)
        guard distance >= configuration.minimumPointSpacing else {
            return .ignoredTooClose
        }

        let relativeTimestamp = max(0, timestamp - activeStroke.startTimestamp)
        guard let point = try? StrokePoint(position: position, timestamp: relativeTimestamp) else {
            return .rejectedInvalidTimestamp
        }

        activeStroke.points.append(point)
        self.activeStroke = activeStroke
        return .appended(
            id: activeStroke.id,
            previousPoint: previousPoint,
            point: point,
            style: activeStroke.style
        )
    }

    func endStroke() -> DrawingEngineEndResult {
        guard let activeStroke else {
            return .noActiveStroke
        }
        self.activeStroke = nil

        guard let stroke = try? Stroke(
            id: activeStroke.id,
            points: activeStroke.points,
            style: activeStroke.style,
            createdAt: activeStroke.createdAt
        ) else {
            return .discarded(id: activeStroke.id)
        }

        completedStrokes.append(stroke)
        return .completed(stroke)
    }

    /// Removes a completed document stroke without affecting in-progress input state.
    @discardableResult
    func removeCompletedStroke(id: UUID) -> (stroke: Stroke, index: Int)? {
        guard let index = completedStrokes.lastIndex(where: { $0.id == id }) else {
            return nil
        }
        return (completedStrokes.remove(at: index), index)
    }

    /// Restores an exact previously completed stroke at its original document order.
    @discardableResult
    func restoreCompletedStroke(_ stroke: Stroke, at index: Int) -> Bool {
        guard
            !completedStrokes.contains(where: { $0.id == stroke.id }),
            completedStrokes.indices.contains(index) || index == completedStrokes.endIndex
        else {
            return false
        }
        completedStrokes.insert(stroke, at: index)
        return true
    }

    /// Replaces a completed stroke in place while preserving its document order.
    /// Editing callers must retain the same stable stroke identifier.
    @discardableResult
    func replaceCompletedStroke(_ stroke: Stroke) -> Int? {
        guard let index = completedStrokes.firstIndex(where: { $0.id == stroke.id }) else {
            return nil
        }
        completedStrokes[index] = stroke
        return index
    }

    @discardableResult
    func cancelStroke() -> UUID? {
        defer { activeStroke = nil }
        return activeStroke?.id
    }
}
