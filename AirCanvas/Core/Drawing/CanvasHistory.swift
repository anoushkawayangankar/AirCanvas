import Foundation

/// A domain-level operation that can later be extended for document editing.
enum CanvasAction: Equatable, Sendable {
    case addStroke(Stroke)
    case deleteStroke(Stroke, originalIndex: Int)
    case moveStroke(before: Stroke, after: Stroke)

    var stroke: Stroke {
        switch self {
        case .addStroke(let stroke):
            stroke
        case .deleteStroke(let stroke, _):
            stroke
        case .moveStroke(_, let after):
            after
        }
    }
}

struct CanvasHistoryConfiguration: Equatable, Sendable {
    /// One hundred actions provides useful recovery for a drawing session while bounding retained stroke data.
    static let standard = CanvasHistoryConfiguration(maximumActionCount: 100)

    let maximumActionCount: Int

    init(maximumActionCount: Int) {
        precondition(maximumActionCount > 0, "Canvas history must retain at least one action.")
        self.maximumActionCount = maximumActionCount
    }
}

/// Bounded action history. It records actions but never owns the current Canvas document.
struct CanvasHistory: Equatable, Sendable {
    private(set) var undoActions: [CanvasAction] = []
    private(set) var redoActions: [CanvasAction] = []

    private let configuration: CanvasHistoryConfiguration

    init(configuration: CanvasHistoryConfiguration = .standard) {
        self.configuration = configuration
    }

    var canUndo: Bool {
        !undoActions.isEmpty
    }

    var canRedo: Bool {
        !redoActions.isEmpty
    }

    var nextUndoAction: CanvasAction? {
        undoActions.last
    }

    var nextRedoAction: CanvasAction? {
        redoActions.last
    }

    mutating func record(_ action: CanvasAction) {
        undoActions.append(action)
        if undoActions.count > configuration.maximumActionCount {
            undoActions.removeFirst(undoActions.count - configuration.maximumActionCount)
        }
        redoActions.removeAll(keepingCapacity: true)
    }

    /// Moves the current undo action to redo after its inverse has updated the document.
    @discardableResult
    mutating func commitUndo() -> CanvasAction? {
        guard let action = undoActions.popLast() else {
            return nil
        }
        redoActions.append(action)
        return action
    }

    /// Moves the current redo action back to undo after it has updated the document.
    @discardableResult
    mutating func commitRedo() -> CanvasAction? {
        guard let action = redoActions.popLast() else {
            return nil
        }
        undoActions.append(action)
        return action
    }
}
