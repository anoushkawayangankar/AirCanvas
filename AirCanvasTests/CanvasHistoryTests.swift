import XCTest
@testable import AirCanvas

final class CanvasHistoryTests: XCTestCase {
    func testInitialHistoryHasNoUndoOrRedo() {
        let history = CanvasHistory()

        XCTAssertFalse(history.canUndo)
        XCTAssertFalse(history.canRedo)
        XCTAssertNil(history.nextUndoAction)
        XCTAssertNil(history.nextRedoAction)
    }

    func testRecordCreatesUndoableAddStrokeActionAndClearsRedo() throws {
        var history = CanvasHistory()
        let first = try makeStroke(x: 0)
        let second = try makeStroke(x: 1)

        history.record(.addStroke(first))
        _ = history.commitUndo()
        history.record(.addStroke(second))

        XCTAssertEqual(history.nextUndoAction, .addStroke(second))
        XCTAssertTrue(history.canUndo)
        XCTAssertFalse(history.canRedo)
        XCTAssertNil(history.nextRedoAction)
    }

    func testUndoAndRedoMoveActionsBetweenStacksInReverseOrder() throws {
        var history = CanvasHistory()
        let first = try makeStroke(x: 0)
        let second = try makeStroke(x: 1)
        let third = try makeStroke(x: 2)
        history.record(.addStroke(first))
        history.record(.addStroke(second))
        history.record(.addStroke(third))

        XCTAssertEqual(history.nextUndoAction, .addStroke(third))
        XCTAssertEqual(history.commitUndo(), .addStroke(third))
        XCTAssertEqual(history.commitUndo(), .addStroke(second))
        XCTAssertEqual(history.nextRedoAction, .addStroke(second))
        XCTAssertEqual(history.commitRedo(), .addStroke(second))
        XCTAssertEqual(history.commitRedo(), .addStroke(third))

        XCTAssertEqual(history.nextUndoAction, .addStroke(third))
        XCTAssertFalse(history.canRedo)
    }

    func testHistoryLimitDiscardsOnlyOldestUndoAction() throws {
        var history = CanvasHistory(configuration: CanvasHistoryConfiguration(maximumActionCount: 2))
        let first = try makeStroke(x: 0)
        let second = try makeStroke(x: 1)
        let third = try makeStroke(x: 2)
        history.record(.addStroke(first))
        history.record(.addStroke(second))
        history.record(.addStroke(third))

        XCTAssertEqual(history.undoActions, [.addStroke(second), .addStroke(third)])
        XCTAssertEqual(history.commitUndo(), .addStroke(third))
        XCTAssertEqual(history.commitUndo(), .addStroke(second))
        XCTAssertNil(history.commitUndo())
        XCTAssertEqual(history.redoActions, [.addStroke(third), .addStroke(second)])
    }

    func testRepeatedUndoRedoDoesNotAlterActionStrokeValues() throws {
        var history = CanvasHistory()
        let style = try BrushStyle(color: .canvasViolet, thickness: 0.018)
        let stroke = try makeStroke(x: 2, style: style)
        history.record(.addStroke(stroke))

        for _ in 0 ..< 20 {
            XCTAssertEqual(history.commitUndo(), .addStroke(stroke))
            XCTAssertEqual(history.commitRedo(), .addStroke(stroke))
        }

        XCTAssertEqual(history.nextUndoAction?.stroke.id, stroke.id)
        XCTAssertEqual(history.nextUndoAction?.stroke.style, style)
    }

    func testDeleteStrokeActionRetainsExactStrokeAndOriginalIndex() throws {
        var history = CanvasHistory()
        let stroke = try makeStroke(x: 2)
        let action = CanvasAction.deleteStroke(stroke, originalIndex: 1)

        history.record(action)

        XCTAssertEqual(history.nextUndoAction, action)
        XCTAssertEqual(history.commitUndo(), action)
        XCTAssertEqual(history.nextRedoAction, action)
        XCTAssertEqual(history.commitRedo(), action)
        XCTAssertEqual(history.nextUndoAction?.stroke, stroke)
    }

    func testNewDeleteActionInvalidatesRedoHistory() throws {
        var history = CanvasHistory()
        let first = try makeStroke(x: 0)
        let second = try makeStroke(x: 1)
        history.record(.addStroke(first))
        history.record(.addStroke(second))
        _ = history.commitUndo()

        let deleteFirst = CanvasAction.deleteStroke(first, originalIndex: 0)
        history.record(deleteFirst)

        XCTAssertEqual(history.nextUndoAction, deleteFirst)
        XCTAssertFalse(history.canRedo)
        XCTAssertNil(history.nextRedoAction)
    }

    func testMoveActionRetainsExactBeforeAndAfterSnapshots() throws {
        var history = CanvasHistory()
        let before = try makeStroke(x: 0)
        let after = try makeStroke(x: 1, style: before.style)
        let action = CanvasAction.moveStroke(before: before, after: after)

        history.record(action)

        XCTAssertEqual(history.nextUndoAction, action)
        XCTAssertEqual(history.nextUndoAction?.stroke, after)
        XCTAssertEqual(history.commitUndo(), action)
        XCTAssertEqual(history.nextRedoAction, action)
        XCTAssertEqual(history.commitRedo(), action)
    }

    private func makeStroke(x: Float, style: BrushStyle = .defaultStyle) throws -> Stroke {
        try Stroke(
            id: UUID(),
            points: [
                try StrokePoint(position: CanvasPoint3D(x: x, y: 0, z: 0)),
                try StrokePoint(position: CanvasPoint3D(x: x + 0.1, y: 0, z: 0))
            ],
            style: style,
            createdAt: Date(timeIntervalSinceReferenceDate: 10)
        )
    }
}
