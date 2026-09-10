import XCTest
@testable import AirCanvas

final class DrawingEngineTests: XCTestCase {
    func testBeginStrokeCreatesActiveStateAndPreservesInitialPoint() throws {
        let engine = makeEngine()
        let point = try makePoint(x: 0)

        let result = engine.beginStroke(at: point, style: .defaultStyle, timestamp: 10)

        guard case .started(let id, let firstPoint, let style) = result else {
            return XCTFail("Expected stroke to begin")
        }
        XCTAssertEqual(firstPoint.position, point)
        XCTAssertEqual(style, .defaultStyle)
        XCTAssertEqual(engine.activeStrokeID, id)
        XCTAssertTrue(engine.isDrawing)
    }

    func testAppendFiltersNearbyPointsAndAcceptsDistantPoints() throws {
        let engine = makeEngine()
        _ = engine.beginStroke(at: try makePoint(x: 0), style: .defaultStyle, timestamp: 0)

        XCTAssertEqual(
            engine.appendPoint(at: try makePoint(x: 0.02), timestamp: 0.1),
            .ignoredTooClose
        )

        let result = engine.appendPoint(at: try makePoint(x: 0.06), timestamp: 0.2)
        guard case .appended(_, let previousPoint, let point, _) = result else {
            return XCTFail("Expected distant point to append")
        }
        XCTAssertEqual(previousPoint.position, try makePoint(x: 0))
        XCTAssertEqual(point.position, try makePoint(x: 0.06))
    }

    func testEndStrokeProducesCompletedStrokeWithStableIdentifier() throws {
        let engine = makeEngine()
        let begin = engine.beginStroke(at: try makePoint(x: 0), style: .defaultStyle, timestamp: 0)
        guard case .started(let id, _, _) = begin else {
            return XCTFail("Expected stroke to begin")
        }
        _ = engine.appendPoint(at: try makePoint(x: 0.1), timestamp: 0.2)

        let result = engine.endStroke()

        guard case .completed(let stroke) = result else {
            return XCTFail("Expected completed stroke")
        }
        XCTAssertEqual(stroke.id, id)
        XCTAssertEqual(stroke.points.count, 2)
        XCTAssertEqual(engine.completedStrokes, [stroke])
        XCTAssertFalse(engine.isDrawing)
    }

    func testEndStrokeDiscardsAnInadequateStroke() throws {
        let engine = makeEngine()
        let begin = engine.beginStroke(at: try makePoint(x: 0), style: .defaultStyle, timestamp: 0)
        guard case .started(let id, _, _) = begin else {
            return XCTFail("Expected stroke to begin")
        }

        XCTAssertEqual(engine.endStroke(), .discarded(id: id))
        XCTAssertTrue(engine.completedStrokes.isEmpty)
    }

    func testCancelStrokeClearsActiveStateWithoutCompletingIt() throws {
        let engine = makeEngine()
        let begin = engine.beginStroke(at: try makePoint(x: 0), style: .defaultStyle, timestamp: 0)
        guard case .started(let id, _, _) = begin else {
            return XCTFail("Expected stroke to begin")
        }

        XCTAssertEqual(engine.cancelStroke(), id)
        XCTAssertFalse(engine.isDrawing)
        XCTAssertTrue(engine.completedStrokes.isEmpty)
    }

    func testStrokeSnapshotsStyleAtCreation() throws {
        let engine = makeEngine()
        let originalStyle = BrushStyle.defaultStyle
        var settings = BrushSettings(style: originalStyle)
        _ = engine.beginStroke(at: try makePoint(x: 0), style: settings.style, timestamp: 0)
        try settings.update(thickness: 0.02)
        _ = engine.appendPoint(at: try makePoint(x: 0.1), timestamp: 0.1)

        guard case .completed(let stroke) = engine.endStroke() else {
            return XCTFail("Expected completed stroke")
        }
        XCTAssertEqual(stroke.style, originalStyle)
        XCTAssertNotEqual(stroke.style, settings.style)
    }

    func testSecondStrokeDoesNotCorruptTheFirst() throws {
        let engine = makeEngine()
        _ = engine.beginStroke(at: try makePoint(x: 0), style: .defaultStyle, timestamp: 0)
        _ = engine.appendPoint(at: try makePoint(x: 0.1), timestamp: 0.1)
        guard case .completed(let firstStroke) = engine.endStroke() else {
            return XCTFail("Expected first completed stroke")
        }

        _ = engine.beginStroke(at: try makePoint(x: 1), style: .defaultStyle, timestamp: 1)
        _ = engine.appendPoint(at: try makePoint(x: 1.1), timestamp: 1.1)
        _ = engine.endStroke()

        XCTAssertEqual(engine.completedStrokes.first, firstStroke)
        XCTAssertEqual(engine.completedStrokes.count, 2)
    }

    func testPointCapacityPreventsUnboundedSingleStrokeSamples() throws {
        let engine = DrawingEngine(
            configuration: DrawingEngineConfiguration(minimumPointSpacing: 0.01, maximumPointCount: 2)
        )
        _ = engine.beginStroke(at: try makePoint(x: 0), style: .defaultStyle, timestamp: 0)
        _ = engine.appendPoint(at: try makePoint(x: 0.1), timestamp: 0.1)

        XCTAssertEqual(
            engine.appendPoint(at: try makePoint(x: 0.2), timestamp: 0.2),
            .ignoredAtCapacity
        )
    }

    func testReplaceCompletedStrokePreservesDocumentOrder() throws {
        let engine = makeEngine()
        _ = engine.beginStroke(at: try makePoint(x: 0), style: .defaultStyle, timestamp: 0)
        _ = engine.appendPoint(at: try makePoint(x: 0.1), timestamp: 0.1)
        guard case .completed(let first) = engine.endStroke() else { return XCTFail("Expected first stroke") }
        _ = engine.beginStroke(at: try makePoint(x: 1), style: .defaultStyle, timestamp: 1)
        _ = engine.appendPoint(at: try makePoint(x: 1.1), timestamp: 1.1)
        guard case .completed(let second) = engine.endStroke() else { return XCTFail("Expected second stroke") }

        let movedFirst = try XCTUnwrap(first.translated(by: SIMD3(0.5, 0, 0)))
        XCTAssertEqual(engine.replaceCompletedStroke(movedFirst), 0)
        XCTAssertEqual(engine.completedStrokes, [movedFirst, second])
    }

    private func makeEngine() -> DrawingEngine {
        DrawingEngine(
            configuration: DrawingEngineConfiguration(minimumPointSpacing: 0.05, maximumPointCount: 8)
        )
    }

    private func makePoint(x: Float) throws -> CanvasPoint3D {
        try CanvasPoint3D(x: x, y: 0, z: 0)
    }
}
