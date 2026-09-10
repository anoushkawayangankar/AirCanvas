import ARKit
import CoreGraphics
import simd
import XCTest
@testable import AirCanvas

@MainActor
final class CanvasARViewModelTests: XCTestCase {
    func testVisibleActiveCanvasStartsSession() {
        let service = ARSessionServiceSpy()
        let viewModel = makeViewModel(sessionService: service)

        viewModel.canvasDidAppear(isApplicationActive: true)

        XCTAssertEqual(service.startCount, 1)
    }

    func testBackgroundingPausesAndReturningActiveRestartsSession() {
        let service = ARSessionServiceSpy()
        let viewModel = makeViewModel(sessionService: service)
        viewModel.canvasDidAppear(isApplicationActive: true)

        viewModel.applicationActivityDidChange(isActive: false)
        viewModel.applicationActivityDidChange(isActive: true)

        XCTAssertEqual(service.pauseCount, 1)
        XCTAssertEqual(service.startCount, 2)
    }

    func testFailureStateCanBeRetriedWhileCanvasIsActive() {
        let service = ARSessionServiceSpy()
        let viewModel = makeViewModel(sessionService: service)
        viewModel.canvasDidAppear(isApplicationActive: true)
        service.send(.failed(.sessionFailed))

        viewModel.retrySession()

        XCTAssertEqual(viewModel.sessionState, .running(.initializing))
        XCTAssertEqual(service.restartCount, 1)
    }

    func testCanvasDismissalPausesSession() {
        let service = ARSessionServiceSpy()
        let viewModel = makeViewModel(sessionService: service)
        viewModel.canvasDidAppear(isApplicationActive: true)

        viewModel.canvasDidDisappear()

        XCTAssertEqual(service.pauseCount, 1)
    }

    func testBrushSettingsUpdateColorAndClampThicknessToCanvasBounds() {
        let sessionService = ARSessionServiceSpy()
        let viewModel = makeViewModel(sessionService: sessionService)
        viewModel.canvasDidAppear(isApplicationActive: true)
        let initialStartCount = sessionService.startCount

        viewModel.selectBrushColor(.canvasRed)
        viewModel.updateBrushThickness(-1)

        XCTAssertEqual(viewModel.brushSettings.style.color, .canvasRed)
        XCTAssertEqual(
            viewModel.brushSettings.style.thickness,
            CanvasBrushConfiguration.thicknessRange.lowerBound
        )

        viewModel.updateBrushThickness(1)

        XCTAssertEqual(
            viewModel.brushSettings.style.thickness,
            CanvasBrushConfiguration.thicknessRange.upperBound
        )
        XCTAssertEqual(sessionService.startCount, initialStartCount)
        XCTAssertEqual(sessionService.restartCount, 0)
    }

    func testBrushStyleIsSnapshottedForEachStrokeAndPassedToRenderer() {
        let sessionService = ARSessionServiceSpy()
        let renderer = StrokeRendererSpy()
        let viewModel = makeViewModel(
            sessionService: sessionService,
            raycastService: SpatialRaycastServiceSpy(
                results: [
                    makeRaycastResult(x: 0), makeRaycastResult(x: 0.1), makeRaycastResult(x: 0.1),
                    makeRaycastResult(x: 1), makeRaycastResult(x: 1.1), makeRaycastResult(x: 1.1)
                ]
            ),
            strokeRenderer: renderer
        )
        viewModel.canvasDidAppear(isApplicationActive: true)
        sessionService.send(.trackingChanged(.normal))
        viewModel.selectBrushColor(.canvasRed)
        viewModel.updateBrushThickness(0.004)
        let firstStyle = viewModel.brushSettings.style

        viewModel.touchDidBegin(at: .zero, timestamp: 0)
        viewModel.selectBrushColor(.canvasViolet)
        viewModel.updateBrushThickness(0.016)
        viewModel.touchDidMove(at: CGPoint(x: 20, y: 0), timestamp: 0.1)
        viewModel.touchDidEnd(at: CGPoint(x: 20, y: 0), timestamp: 0.1)

        let secondStyle = viewModel.brushSettings.style
        viewModel.touchDidBegin(at: CGPoint(x: 40, y: 0), timestamp: 1)
        viewModel.touchDidMove(at: CGPoint(x: 60, y: 0), timestamp: 1.1)
        viewModel.touchDidEnd(at: CGPoint(x: 60, y: 0), timestamp: 1.1)

        XCTAssertEqual(renderer.beginStyles, [firstStyle, secondStyle])
        XCTAssertEqual(renderer.activePointStyles, [firstStyle, secondStyle])
        XCTAssertEqual(renderer.finalizedStrokes.map(\.style), [firstStyle, secondStyle])
        XCTAssertEqual(viewModel.completedStrokes.map(\.style), [firstStyle, secondStyle])
    }

    func testTouchDrawsACompletedStrokeWhenTrackingIsNormal() {
        let sessionService = ARSessionServiceSpy()
        let raycastService = SpatialRaycastServiceSpy(
            results: [makeRaycastResult(x: 0), makeRaycastResult(x: 0.1), makeRaycastResult(x: 0.1)]
        )
        let strokeRenderer = StrokeRendererSpy()
        let viewModel = makeViewModel(
            sessionService: sessionService,
            raycastService: raycastService,
            strokeRenderer: strokeRenderer
        )
        viewModel.canvasDidAppear(isApplicationActive: true)
        sessionService.send(.trackingChanged(.normal))

        viewModel.touchDidBegin(at: .zero, timestamp: 0)
        viewModel.touchDidMove(at: CGPoint(x: 20, y: 0), timestamp: 0.1)
        viewModel.touchDidEnd(at: CGPoint(x: 20, y: 0), timestamp: 0.1)

        XCTAssertEqual(viewModel.completedStrokes.count, 1)
        XCTAssertEqual(strokeRenderer.beginCount, 1)
        XCTAssertEqual(strokeRenderer.activePointUpdateCount, 1)
        XCTAssertEqual(strokeRenderer.completedStrokeIDs, viewModel.completedStrokes.map(\.id))
        XCTAssertNil(viewModel.placementHint)
        XCTAssertTrue(viewModel.canUndo)
        XCTAssertFalse(viewModel.canRedo)
    }

    func testUndoAndRedoSynchronizeTheDocumentAndRendererWithoutRestartingAR() {
        let sessionService = ARSessionServiceSpy()
        let renderer = StrokeRendererSpy()
        let viewModel = makeViewModel(
            sessionService: sessionService,
            raycastService: SpatialRaycastServiceSpy(
                results: [
                    makeRaycastResult(x: 0), makeRaycastResult(x: 0.1), makeRaycastResult(x: 0.1),
                    makeRaycastResult(x: 1), makeRaycastResult(x: 1.1), makeRaycastResult(x: 1.1)
                ]
            ),
            strokeRenderer: renderer
        )
        viewModel.canvasDidAppear(isApplicationActive: true)
        sessionService.send(.trackingChanged(.normal))

        drawStroke(with: viewModel, start: .zero, end: CGPoint(x: 20, y: 0), timestamp: 0)
        viewModel.selectBrushColor(.canvasRed)
        drawStroke(with: viewModel, start: CGPoint(x: 40, y: 0), end: CGPoint(x: 60, y: 0), timestamp: 1)
        let originalStrokes = viewModel.completedStrokes
        let startCount = sessionService.startCount

        viewModel.undoLastStroke()

        XCTAssertEqual(viewModel.completedStrokes, [originalStrokes[0]])
        XCTAssertEqual(renderer.removedStrokeIDs.last, originalStrokes[1].id)
        XCTAssertTrue(viewModel.canUndo)
        XCTAssertTrue(viewModel.canRedo)
        XCTAssertEqual(sessionService.startCount, startCount)
        XCTAssertEqual(sessionService.restartCount, 0)

        viewModel.redoLastStroke()

        XCTAssertEqual(viewModel.completedStrokes, originalStrokes)
        XCTAssertEqual(renderer.restoredStrokes, [originalStrokes[1]])
        XCTAssertEqual(viewModel.completedStrokes[1].id, originalStrokes[1].id)
        XCTAssertEqual(viewModel.completedStrokes[1].style, originalStrokes[1].style)
        XCTAssertTrue(viewModel.canUndo)
        XCTAssertFalse(viewModel.canRedo)

        for _ in 0 ..< 20 {
            viewModel.undoLastStroke()
            viewModel.redoLastStroke()
        }

        XCTAssertEqual(viewModel.completedStrokes, originalStrokes)
        XCTAssertEqual(viewModel.completedStrokes.map(\.id), originalStrokes.map(\.id))
    }

    func testNewCompletedStrokeInvalidatesRedoHistory() {
        let sessionService = ARSessionServiceSpy()
        let viewModel = makeViewModel(
            sessionService: sessionService,
            raycastService: SpatialRaycastServiceSpy(
                results: [
                    makeRaycastResult(x: 0), makeRaycastResult(x: 0.1), makeRaycastResult(x: 0.1),
                    makeRaycastResult(x: 1), makeRaycastResult(x: 1.1), makeRaycastResult(x: 1.1),
                    makeRaycastResult(x: 2), makeRaycastResult(x: 2.1), makeRaycastResult(x: 2.1)
                ]
            )
        )
        viewModel.canvasDidAppear(isApplicationActive: true)
        sessionService.send(.trackingChanged(.normal))

        drawStroke(with: viewModel, start: .zero, end: CGPoint(x: 20, y: 0), timestamp: 0)
        drawStroke(with: viewModel, start: CGPoint(x: 40, y: 0), end: CGPoint(x: 60, y: 0), timestamp: 1)
        viewModel.undoLastStroke()
        drawStroke(with: viewModel, start: CGPoint(x: 80, y: 0), end: CGPoint(x: 100, y: 0), timestamp: 2)

        XCTAssertEqual(viewModel.completedStrokes.count, 2)
        XCTAssertFalse(viewModel.canRedo)
    }

    func testHistoryLimitDoesNotRemoveOlderCanvasStrokes() {
        let sessionService = ARSessionServiceSpy()
        let viewModel = makeViewModel(
            sessionService: sessionService,
            raycastService: SpatialRaycastServiceSpy(
                results: [
                    makeRaycastResult(x: 0), makeRaycastResult(x: 0.1), makeRaycastResult(x: 0.1),
                    makeRaycastResult(x: 1), makeRaycastResult(x: 1.1), makeRaycastResult(x: 1.1),
                    makeRaycastResult(x: 2), makeRaycastResult(x: 2.1), makeRaycastResult(x: 2.1)
                ]
            ),
            history: CanvasHistory(configuration: CanvasHistoryConfiguration(maximumActionCount: 2))
        )
        viewModel.canvasDidAppear(isApplicationActive: true)
        sessionService.send(.trackingChanged(.normal))

        drawStroke(with: viewModel, start: .zero, end: CGPoint(x: 20, y: 0), timestamp: 0)
        drawStroke(with: viewModel, start: CGPoint(x: 40, y: 0), end: CGPoint(x: 60, y: 0), timestamp: 1)
        drawStroke(with: viewModel, start: CGPoint(x: 80, y: 0), end: CGPoint(x: 100, y: 0), timestamp: 2)
        let firstStroke = viewModel.completedStrokes[0]

        viewModel.undoLastStroke()
        viewModel.undoLastStroke()

        XCTAssertEqual(viewModel.completedStrokes, [firstStroke])
        XCTAssertFalse(viewModel.canUndo)
    }

    func testHistoryControlsAreUnavailableWhileDrawingAndCancelledStrokesAreNotRecorded() {
        let sessionService = ARSessionServiceSpy()
        let renderer = StrokeRendererSpy()
        let viewModel = makeViewModel(
            sessionService: sessionService,
            raycastService: SpatialRaycastServiceSpy(results: [makeRaycastResult(x: 0)]),
            strokeRenderer: renderer
        )
        viewModel.canvasDidAppear(isApplicationActive: true)
        sessionService.send(.trackingChanged(.normal))
        viewModel.touchDidBegin(at: .zero, timestamp: 0)

        XCTAssertTrue(viewModel.isDrawing)
        XCTAssertFalse(viewModel.canUndo)
        XCTAssertFalse(viewModel.canRedo)
        viewModel.undoLastStroke()
        viewModel.touchDidCancel()

        XCTAssertTrue(viewModel.completedStrokes.isEmpty)
        XCTAssertFalse(viewModel.canUndo)
        XCTAssertFalse(viewModel.canRedo)
        XCTAssertEqual(renderer.removedStrokeIDs.count, 1)
    }

    func testTouchDoesNotRaycastWhenTrackingIsLimited() {
        let sessionService = ARSessionServiceSpy()
        let raycastService = SpatialRaycastServiceSpy(results: [makeRaycastResult(x: 0)])
        let strokeRenderer = StrokeRendererSpy()
        let viewModel = makeViewModel(
            sessionService: sessionService,
            raycastService: raycastService,
            strokeRenderer: strokeRenderer
        )
        viewModel.canvasDidAppear(isApplicationActive: true)
        sessionService.send(.trackingChanged(.limited(.insufficientFeatures)))

        viewModel.touchDidBegin(at: .zero, timestamp: 0)

        XCTAssertTrue(raycastService.requestedPoints.isEmpty)
        XCTAssertEqual(strokeRenderer.beginCount, 0)
        XCTAssertEqual(viewModel.placementHint, "Point toward a well-lit, textured area.")
    }

    func testInvalidInitialRaycastDoesNotBeginDrawing() {
        let sessionService = ARSessionServiceSpy()
        let raycastService = SpatialRaycastServiceSpy(results: [nil])
        let strokeRenderer = StrokeRendererSpy()
        let viewModel = makeViewModel(
            sessionService: sessionService,
            raycastService: raycastService,
            strokeRenderer: strokeRenderer
        )
        viewModel.canvasDidAppear(isApplicationActive: true)
        sessionService.send(.trackingChanged(.normal))

        viewModel.touchDidBegin(at: .zero, timestamp: 0)

        XCTAssertFalse(viewModel.isDrawing)
        XCTAssertEqual(strokeRenderer.beginCount, 0)
        XCTAssertEqual(
            viewModel.placementHint,
            "No surface found. Move slowly and point toward a visible surface."
        )
        XCTAssertFalse(viewModel.canUndo)
    }

    func testBackgroundingCancelsAnActiveStroke() {
        let sessionService = ARSessionServiceSpy()
        let strokeRenderer = StrokeRendererSpy()
        let viewModel = makeViewModel(
            sessionService: sessionService,
            raycastService: SpatialRaycastServiceSpy(results: [makeRaycastResult(x: 0)]),
            strokeRenderer: strokeRenderer
        )
        viewModel.canvasDidAppear(isApplicationActive: true)
        sessionService.send(.trackingChanged(.normal))
        viewModel.touchDidBegin(at: .zero, timestamp: 0)

        viewModel.applicationActivityDidChange(isActive: false)

        XCTAssertFalse(viewModel.isDrawing)
        XCTAssertEqual(strokeRenderer.removedStrokeIDs.count, 1)
        XCTAssertTrue(viewModel.completedStrokes.isEmpty)
    }

    func testLimitedTrackingCancelsAnActiveStroke() {
        let sessionService = ARSessionServiceSpy()
        let strokeRenderer = StrokeRendererSpy()
        let viewModel = makeViewModel(
            sessionService: sessionService,
            raycastService: SpatialRaycastServiceSpy(results: [makeRaycastResult(x: 0)]),
            strokeRenderer: strokeRenderer
        )
        viewModel.canvasDidAppear(isApplicationActive: true)
        sessionService.send(.trackingChanged(.normal))
        viewModel.touchDidBegin(at: .zero, timestamp: 0)

        sessionService.send(.trackingChanged(.limited(.excessiveMotion)))

        XCTAssertFalse(viewModel.isDrawing)
        XCTAssertEqual(strokeRenderer.removedStrokeIDs.count, 1)
        XCTAssertTrue(viewModel.completedStrokes.isEmpty)
    }

    func testSelectModeSelectsTheRendererMappedStrokeAndClearsWhenReturningToDraw() {
        let sessionService = ARSessionServiceSpy()
        let renderer = StrokeRendererSpy()
        let viewModel = makeViewModel(
            sessionService: sessionService,
            raycastService: SpatialRaycastServiceSpy(
                results: [makeRaycastResult(x: 0), makeRaycastResult(x: 0.1), makeRaycastResult(x: 0.1)]
            ),
            strokeRenderer: renderer
        )
        viewModel.canvasDidAppear(isApplicationActive: true)
        sessionService.send(.trackingChanged(.normal))
        drawStroke(with: viewModel, start: .zero, end: CGPoint(x: 20, y: 0), timestamp: 0)
        guard let strokeID = viewModel.completedStrokes.first?.id else {
            return XCTFail("Expected a completed stroke to select")
        }

        viewModel.selectTool(.select)
        renderer.nextHitStrokeID = strokeID
        viewModel.selectionDidRequest(at: CGPoint(x: 10, y: 10))

        XCTAssertEqual(viewModel.canvasTool, .select)
        XCTAssertEqual(viewModel.selectedStrokeID, strokeID)
        XCTAssertEqual(renderer.selectionUpdates.last!, strokeID)
        XCTAssertTrue(viewModel.canDeleteSelectedStroke)

        viewModel.selectTool(.draw)

        XCTAssertEqual(viewModel.canvasTool, .draw)
        XCTAssertNil(viewModel.selectedStrokeID)
        XCTAssertEqual(renderer.selectionUpdates.last!, nil)
    }

    func testEmptySpaceTapDeselectsCurrentStrokeWithoutChangingDocument() {
        let sessionService = ARSessionServiceSpy()
        let renderer = StrokeRendererSpy()
        let viewModel = makeViewModel(
            sessionService: sessionService,
            raycastService: SpatialRaycastServiceSpy(
                results: [makeRaycastResult(x: 0), makeRaycastResult(x: 0.1), makeRaycastResult(x: 0.1)]
            ),
            strokeRenderer: renderer
        )
        viewModel.canvasDidAppear(isApplicationActive: true)
        sessionService.send(.trackingChanged(.normal))
        drawStroke(with: viewModel, start: .zero, end: CGPoint(x: 20, y: 0), timestamp: 0)
        renderer.nextHitStrokeID = viewModel.completedStrokes[0].id
        viewModel.selectTool(.select)
        viewModel.selectionDidRequest(at: .zero)

        renderer.nextHitStrokeID = nil
        viewModel.selectionDidRequest(at: CGPoint(x: 300, y: 300))

        XCTAssertNil(viewModel.selectedStrokeID)
        XCTAssertEqual(viewModel.completedStrokes.count, 1)
        XCTAssertEqual(renderer.selectionUpdates.last!, nil)
    }

    func testSelectingAnotherStrokeReplacesTheCurrentSelection() {
        let sessionService = ARSessionServiceSpy()
        let renderer = StrokeRendererSpy()
        let viewModel = makeViewModel(
            sessionService: sessionService,
            raycastService: SpatialRaycastServiceSpy(
                results: [
                    makeRaycastResult(x: 0), makeRaycastResult(x: 0.1), makeRaycastResult(x: 0.1),
                    makeRaycastResult(x: 1), makeRaycastResult(x: 1.1), makeRaycastResult(x: 1.1)
                ]
            ),
            strokeRenderer: renderer
        )
        viewModel.canvasDidAppear(isApplicationActive: true)
        sessionService.send(.trackingChanged(.normal))
        drawStroke(with: viewModel, start: .zero, end: CGPoint(x: 20, y: 0), timestamp: 0)
        drawStroke(with: viewModel, start: CGPoint(x: 40, y: 0), end: CGPoint(x: 60, y: 0), timestamp: 1)
        let strokes = viewModel.completedStrokes

        viewModel.selectTool(.select)
        renderer.nextHitStrokeID = strokes[0].id
        viewModel.selectionDidRequest(at: .zero)
        renderer.nextHitStrokeID = strokes[1].id
        viewModel.selectionDidRequest(at: CGPoint(x: 50, y: 0))

        XCTAssertEqual(viewModel.selectedStrokeID, strokes[1].id)
        XCTAssertEqual(renderer.selectionUpdates, [strokes[0].id, strokes[1].id])
    }

    func testDeleteUndoAndRedoRestoreExactStrokeAtOriginalDocumentPosition() {
        let sessionService = ARSessionServiceSpy()
        let renderer = StrokeRendererSpy()
        let viewModel = makeViewModel(
            sessionService: sessionService,
            raycastService: SpatialRaycastServiceSpy(
                results: [
                    makeRaycastResult(x: 0), makeRaycastResult(x: 0.1), makeRaycastResult(x: 0.1),
                    makeRaycastResult(x: 1), makeRaycastResult(x: 1.1), makeRaycastResult(x: 1.1)
                ]
            ),
            strokeRenderer: renderer
        )
        viewModel.canvasDidAppear(isApplicationActive: true)
        sessionService.send(.trackingChanged(.normal))
        drawStroke(with: viewModel, start: .zero, end: CGPoint(x: 20, y: 0), timestamp: 0)
        viewModel.selectBrushColor(.canvasRed)
        viewModel.updateBrushThickness(0.016)
        drawStroke(with: viewModel, start: CGPoint(x: 40, y: 0), end: CGPoint(x: 60, y: 0), timestamp: 1)
        let original = viewModel.completedStrokes

        viewModel.selectTool(.select)
        renderer.nextHitStrokeID = original[0].id
        viewModel.selectionDidRequest(at: .zero)
        viewModel.deleteSelectedStroke()

        XCTAssertEqual(viewModel.completedStrokes, [original[1]])
        XCTAssertEqual(renderer.removedStrokeIDs.last, original[0].id)
        XCTAssertNil(viewModel.selectedStrokeID)
        XCTAssertTrue(viewModel.canUndo)

        viewModel.undoLastStroke()

        XCTAssertEqual(viewModel.completedStrokes, original)
        XCTAssertEqual(renderer.restoredStrokes.last, original[0])
        XCTAssertNil(viewModel.selectedStrokeID)

        viewModel.redoLastStroke()

        XCTAssertEqual(viewModel.completedStrokes, [original[1]])
        XCTAssertEqual(renderer.removedStrokeIDs.last, original[0].id)
        XCTAssertFalse(viewModel.completedStrokes.contains(where: { $0.id == original[0].id }))
    }

    func testUndoingAnAddedSelectedStrokeClearsStaleSelection() {
        let sessionService = ARSessionServiceSpy()
        let renderer = StrokeRendererSpy()
        let viewModel = makeViewModel(
            sessionService: sessionService,
            raycastService: SpatialRaycastServiceSpy(
                results: [makeRaycastResult(x: 0), makeRaycastResult(x: 0.1), makeRaycastResult(x: 0.1)]
            ),
            strokeRenderer: renderer
        )
        viewModel.canvasDidAppear(isApplicationActive: true)
        sessionService.send(.trackingChanged(.normal))
        drawStroke(with: viewModel, start: .zero, end: CGPoint(x: 20, y: 0), timestamp: 0)
        let strokeID = viewModel.completedStrokes[0].id
        viewModel.selectTool(.select)
        renderer.nextHitStrokeID = strokeID
        viewModel.selectionDidRequest(at: .zero)

        viewModel.undoLastStroke()

        XCTAssertTrue(viewModel.completedStrokes.isEmpty)
        XCTAssertNil(viewModel.selectedStrokeID)
        XCTAssertEqual(renderer.selectionUpdates.last!, nil)
    }

    func testMixedAddAndDeleteHistoryKeepsDocumentOrderDeterministic() {
        let sessionService = ARSessionServiceSpy()
        let renderer = StrokeRendererSpy()
        let viewModel = makeViewModel(
            sessionService: sessionService,
            raycastService: SpatialRaycastServiceSpy(
                results: [
                    makeRaycastResult(x: 0), makeRaycastResult(x: 0.1), makeRaycastResult(x: 0.1),
                    makeRaycastResult(x: 1), makeRaycastResult(x: 1.1), makeRaycastResult(x: 1.1),
                    makeRaycastResult(x: 2), makeRaycastResult(x: 2.1), makeRaycastResult(x: 2.1)
                ]
            ),
            strokeRenderer: renderer
        )
        viewModel.canvasDidAppear(isApplicationActive: true)
        sessionService.send(.trackingChanged(.normal))
        drawStroke(with: viewModel, start: .zero, end: CGPoint(x: 20, y: 0), timestamp: 0)
        drawStroke(with: viewModel, start: CGPoint(x: 40, y: 0), end: CGPoint(x: 60, y: 0), timestamp: 1)
        let first = viewModel.completedStrokes[0]
        let second = viewModel.completedStrokes[1]

        viewModel.selectTool(.select)
        renderer.nextHitStrokeID = first.id
        viewModel.selectionDidRequest(at: .zero)
        viewModel.deleteSelectedStroke()
        viewModel.selectTool(.draw)
        drawStroke(with: viewModel, start: CGPoint(x: 80, y: 0), end: CGPoint(x: 100, y: 0), timestamp: 2)
        let third = viewModel.completedStrokes[1]

        viewModel.undoLastStroke()
        XCTAssertEqual(viewModel.completedStrokes, [second])
        viewModel.undoLastStroke()
        XCTAssertEqual(viewModel.completedStrokes, [first, second])
        viewModel.undoLastStroke()
        XCTAssertEqual(viewModel.completedStrokes, [first])

        viewModel.redoLastStroke()
        viewModel.redoLastStroke()
        viewModel.redoLastStroke()

        XCTAssertEqual(viewModel.completedStrokes, [second, third])
    }

    func testRepeatedDeleteUndoRedoDoesNotDuplicateTheRestoredStroke() {
        let sessionService = ARSessionServiceSpy()
        let renderer = StrokeRendererSpy()
        let viewModel = makeViewModel(
            sessionService: sessionService,
            raycastService: SpatialRaycastServiceSpy(
                results: [makeRaycastResult(x: 0), makeRaycastResult(x: 0.1), makeRaycastResult(x: 0.1)]
            ),
            strokeRenderer: renderer
        )
        viewModel.canvasDidAppear(isApplicationActive: true)
        sessionService.send(.trackingChanged(.normal))
        drawStroke(with: viewModel, start: .zero, end: CGPoint(x: 20, y: 0), timestamp: 0)
        let stroke = viewModel.completedStrokes[0]
        viewModel.selectTool(.select)
        renderer.nextHitStrokeID = stroke.id
        viewModel.selectionDidRequest(at: .zero)
        viewModel.deleteSelectedStroke()

        for _ in 0 ..< 20 {
            viewModel.undoLastStroke()
            XCTAssertEqual(viewModel.completedStrokes, [stroke])
            viewModel.redoLastStroke()
            XCTAssertTrue(viewModel.completedStrokes.isEmpty)
        }
    }

    // MARK: - Milestone 19 hand drawing

    func testConfirmedHandPinchCreatesNormalStrokeWithCurrentBrushAndHistory() {
        let sessionService = ARSessionServiceSpy()
        let renderer = StrokeRendererSpy()
        let viewModel = makeViewModel(
            sessionService: sessionService,
            raycastService: SpatialRaycastServiceSpy(
                results: [makeRaycastResult(x: 0), makeRaycastResult(x: 0.2)]
            ),
            strokeRenderer: renderer
        )
        viewModel.canvasDidAppear(isApplicationActive: true)
        sessionService.send(.trackingChanged(.normal))
        viewModel.selectBrushColor(.canvasRed)
        viewModel.updateBrushThickness(0.012)
        let expectedStyle = viewModel.brushSettings.style

        viewModel.updateSpatialFingertip(.tracking(.zero))
        viewModel.handTrackingDidUpdate(hand(distance: 0.08), timestamp: 0)
        viewModel.handTrackingDidUpdate(hand(distance: 0.08), timestamp: 0.13)

        XCTAssertEqual(viewModel.drawingInputSource, .hand)
        XCTAssertTrue(viewModel.isDrawing)
        XCTAssertEqual(renderer.beginStyles, [expectedStyle])

        viewModel.updateSpatialFingertip(.tracking(CGPoint(x: 10, y: 0)))
        viewModel.handTrackingDidUpdate(hand(distance: 0.16), timestamp: 0.2)
        viewModel.handTrackingDidUpdate(hand(distance: 0.16), timestamp: 0.33)

        XCTAssertEqual(viewModel.drawingInputSource, .none)
        XCTAssertFalse(viewModel.isDrawing)
        XCTAssertEqual(viewModel.completedStrokes.count, 1)
        XCTAssertEqual(viewModel.completedStrokes[0].style, expectedStyle)
        XCTAssertEqual(renderer.finalizedStrokes.count, 1)
        XCTAssertTrue(viewModel.canUndo)

        viewModel.undoLastStroke()
        XCTAssertTrue(viewModel.completedStrokes.isEmpty)
        viewModel.redoLastStroke()
        XCTAssertEqual(viewModel.completedStrokes.count, 1)
    }

    func testPinchWithoutInitialSpatialPointDoesNotBeginLaterDuringSamePinch() {
        let sessionService = ARSessionServiceSpy()
        let viewModel = makeViewModel(
            sessionService: sessionService,
            raycastService: SpatialRaycastServiceSpy(results: [makeRaycastResult(x: 0)])
        )
        viewModel.canvasDidAppear(isApplicationActive: true)
        sessionService.send(.trackingChanged(.normal))

        viewModel.handTrackingDidUpdate(hand(distance: 0.08), timestamp: 0)
        viewModel.handTrackingDidUpdate(hand(distance: 0.08), timestamp: 0.13)
        XCTAssertEqual(viewModel.drawingInputSource, .none)

        viewModel.updateSpatialFingertip(.tracking(.zero))
        XCTAssertFalse(viewModel.isDrawing)
        XCTAssertEqual(viewModel.drawingInputSource, .none)
    }

    func testPinchCandidateAndCursorMovementNeverStartHandDrawing() {
        let sessionService = ARSessionServiceSpy()
        let viewModel = makeViewModel(
            sessionService: sessionService,
            raycastService: SpatialRaycastServiceSpy(results: [makeRaycastResult(x: 0)])
        )
        viewModel.canvasDidAppear(isApplicationActive: true)
        sessionService.send(.trackingChanged(.normal))

        viewModel.updateSpatialFingertip(.tracking(.zero))
        XCTAssertFalse(viewModel.isDrawing)
        viewModel.handTrackingDidUpdate(hand(distance: 0.08), timestamp: 0)
        XCTAssertEqual(viewModel.pinchGestureState, .pinchCandidate)
        XCTAssertFalse(viewModel.isDrawing)
        XCTAssertEqual(viewModel.drawingInputSource, .none)
    }

    func testOnboardingPinchVerificationObservesProductionEventsWithoutDocumentMutation() {
        let sessionService = ARSessionServiceSpy()
        let viewModel = makeViewModel(
            sessionService: sessionService,
            raycastService: SpatialRaycastServiceSpy(results: [makeRaycastResult(x: 0)])
        )
        viewModel.canvasDidAppear(isApplicationActive: true)
        sessionService.send(.trackingChanged(.normal))
        viewModel.updateSpatialFingertip(.tracking(.zero))
        var events: [PinchGestureEvent] = []
        viewModel.setOnboardingPinchVerification(active: true) { events.append($0) }

        beginHandPinch(on: viewModel)
        endHandPinch(on: viewModel)

        XCTAssertEqual(events, [.began, .ended])
        XCTAssertTrue(viewModel.completedStrokes.isEmpty)
        XCTAssertFalse(viewModel.isDrawing)
        XCTAssertEqual(viewModel.drawingInputSource, .none)
        XCTAssertFalse(viewModel.canUndo)
    }

    func testOnboardingFirstStrokeObserverReceivesOnlyNormalCommittedHandStroke() {
        let sessionService = ARSessionServiceSpy()
        let viewModel = makeViewModel(
            sessionService: sessionService,
            raycastService: SpatialRaycastServiceSpy(results: [makeRaycastResult(x: 0), makeRaycastResult(x: 0.2)])
        )
        viewModel.canvasDidAppear(isApplicationActive: true)
        sessionService.send(.trackingChanged(.normal))
        var committed: [(Stroke.ID, UUID)] = []
        viewModel.setOnboardingCommittedStrokeObserver { committed.append(($0, $1)) }

        beginHandStroke(on: viewModel)
        XCTAssertTrue(committed.isEmpty)
        viewModel.updateSpatialFingertip(.tracking(CGPoint(x: 10, y: 0)))
        endHandPinch(on: viewModel)

        XCTAssertEqual(committed.count, 1)
        XCTAssertEqual(committed.first?.0, viewModel.completedStrokes.first?.id)
        XCTAssertEqual(committed.first?.1, viewModel.activeProject.id)
        XCTAssertTrue(viewModel.canUndo)
    }

    func testSkippingOnboardingFirstStrokeCancelsActiveStrokeWithoutCommit() {
        let sessionService = ARSessionServiceSpy()
        let viewModel = makeHandDrawingViewModel(sessionService: sessionService)
        beginHandStroke(on: viewModel)
        XCTAssertTrue(viewModel.isDrawing)
        viewModel.cancelOnboardingFirstStroke()
        XCTAssertFalse(viewModel.isDrawing)
        XCTAssertEqual(viewModel.drawingInputSource, .none)
        XCTAssertTrue(viewModel.completedStrokes.isEmpty)
        XCTAssertFalse(viewModel.canUndo)
    }

    func testTouchSelectionDragCommitsOneSnapshotMoveAndUndoRedo() throws {
        let original = try makeStroke(startX: 0)
        let sessionService = ARSessionServiceSpy()
        let renderer = StrokeRendererSpy()
        let viewModel = makeViewModel(
            sessionService: sessionService,
            raycastService: SpatialRaycastServiceSpy(results: [makeRaycastResult(x: 0), makeRaycastResult(x: 0.2), makeRaycastResult(x: 0.2)]),
            strokeRenderer: renderer,
            project: try CanvasProject(name: "Touch Move", strokes: [original])
        )
        viewModel.canvasDidAppear(isApplicationActive: true)
        sessionService.send(.trackingChanged(.normal))
        viewModel.selectTool(.select)
        renderer.nextHitStrokeID = original.id
        viewModel.selectionDidRequest(at: .zero)

        viewModel.touchSelectionDragBegan(at: .zero)
        viewModel.touchSelectionDragMoved(at: CGPoint(x: 10, y: 0))
        viewModel.touchSelectionDragEnded(at: CGPoint(x: 10, y: 0))
        let moved = try XCTUnwrap(viewModel.completedStrokes.first)
        XCTAssertNotEqual(moved, original)
        XCTAssertEqual(moved.id, original.id)
        viewModel.undoLastStroke()
        XCTAssertEqual(viewModel.completedStrokes, [original])
        viewModel.redoLastStroke()
        XCTAssertEqual(viewModel.completedStrokes, [moved])
    }

    func testHandAndTouchDrawingMutuallyExcludeEachOther() {
        let sessionService = ARSessionServiceSpy()
        let viewModel = makeViewModel(
            sessionService: sessionService,
            raycastService: SpatialRaycastServiceSpy(
                results: [makeRaycastResult(x: 0), makeRaycastResult(x: 0.2), makeRaycastResult(x: 0.4)]
            )
        )
        viewModel.canvasDidAppear(isApplicationActive: true)
        sessionService.send(.trackingChanged(.normal))

        viewModel.touchDidBegin(at: .zero, timestamp: 0)
        XCTAssertEqual(viewModel.drawingInputSource, .touch)
        viewModel.updateSpatialFingertip(.tracking(.zero))
        viewModel.handTrackingDidUpdate(hand(distance: 0.08), timestamp: 0)
        viewModel.handTrackingDidUpdate(hand(distance: 0.08), timestamp: 0.13)
        XCTAssertEqual(viewModel.drawingInputSource, .touch)
        viewModel.touchDidCancel()

        viewModel.updateSpatialFingertip(.tracking(CGPoint(x: 10, y: 0)))
        viewModel.handTrackingDidUpdate(hand(distance: 0.16), timestamp: 0.2)
        viewModel.handTrackingDidUpdate(hand(distance: 0.16), timestamp: 0.33)
        viewModel.handTrackingDidUpdate(hand(distance: 0.08), timestamp: 1)
        viewModel.handTrackingDidUpdate(hand(distance: 0.08), timestamp: 1.13)
        XCTAssertEqual(viewModel.drawingInputSource, .hand)

        viewModel.touchDidBegin(at: .zero, timestamp: 2)
        XCTAssertEqual(viewModel.drawingInputSource, .hand)
    }

    func testHandDrawingIsCancelledByTrackingLossModeChangeBackgroundAndDismissal() {
        let sessionService = ARSessionServiceSpy()
        let viewModel = makeHandDrawingViewModel(sessionService: sessionService)

        sessionService.send(.trackingChanged(.limited(.insufficientFeatures)))
        XCTAssertEqual(viewModel.drawingInputSource, .none)
        XCTAssertFalse(viewModel.isDrawing)

        beginHandStroke(on: viewModel)
        viewModel.selectTool(.select)
        XCTAssertEqual(viewModel.drawingInputSource, .none)
        XCTAssertFalse(viewModel.isDrawing)

        viewModel.selectTool(.draw)
        beginHandStroke(on: viewModel)
        viewModel.applicationActivityDidChange(isActive: false)
        XCTAssertEqual(viewModel.drawingInputSource, .none)
        XCTAssertFalse(viewModel.isDrawing)

        viewModel.applicationActivityDidChange(isActive: true)
        sessionService.send(.trackingChanged(.normal))
        beginHandStroke(on: viewModel)
        viewModel.canvasDidDisappear()
        XCTAssertEqual(viewModel.drawingInputSource, .none)
        XCTAssertFalse(viewModel.isDrawing)
    }

    func testHandLossCancelsWithoutRecordingHistoryAndNewPinchStartsCleanly() {
        let sessionService = ARSessionServiceSpy()
        let viewModel = makeHandDrawingViewModel(sessionService: sessionService)

        viewModel.handTrackingDidUpdate(.noHand, timestamp: 1)
        XCTAssertEqual(viewModel.drawingInputSource, .none)
        XCTAssertFalse(viewModel.isDrawing)
        XCTAssertTrue(viewModel.completedStrokes.isEmpty)
        XCTAssertFalse(viewModel.canUndo)

        beginHandStroke(on: viewModel, timestamp: 2)
        XCTAssertEqual(viewModel.drawingInputSource, .hand)
    }

    func testNonDrawingToolAndUnresolvedRelocalizationDenyHandStrokeStart() throws {
        let sessionService = ARSessionServiceSpy()
        let viewModel = makeViewModel(
            sessionService: sessionService,
            raycastService: SpatialRaycastServiceSpy(results: [makeRaycastResult(x: 0)]),
            project: try CanvasProject(
                name: "Spatial Canvas",
                spatialState: SpatialCanvasState(mappingQuality: .mapped)
            ),
            relocalizationState: .scanning
        )
        viewModel.canvasDidAppear(isApplicationActive: true)
        sessionService.send(.trackingChanged(.normal))
        // The normal tracking event localizes this test project. Switch to Select to
        // prove that a confirmed pinch still cannot own drawing input.
        viewModel.selectTool(.select)
        viewModel.updateSpatialFingertip(.tracking(.zero))
        viewModel.handTrackingDidUpdate(hand(distance: 0.08), timestamp: 0)
        viewModel.handTrackingDidUpdate(hand(distance: 0.08), timestamp: 0.13)

        XCTAssertEqual(viewModel.drawingInputSource, .none)
        XCTAssertFalse(viewModel.isDrawing)
    }

    // MARK: - Milestone 20 hand selection and translation

    func testEraseModeHoverIsNonDestructiveAndConfirmedPinchDeletesOnce() throws {
        let first = try makeStroke(startX: 0)
        let second = try makeStroke(startX: 1)
        let sessionService = ARSessionServiceSpy()
        let viewModel = makeViewModel(
            sessionService: sessionService,
            raycastService: SpatialRaycastServiceSpy(results: [makeRaycastResult(x: 0.05), makeRaycastResult(x: 1.05)]),
            project: try CanvasProject(name: "Erase", strokes: [first, second])
        )
        viewModel.canvasDidAppear(isApplicationActive: true)
        sessionService.send(.trackingChanged(.normal))
        viewModel.selectTool(.erase)
        viewModel.updateSpatialFingertip(.tracking(.zero))

        XCTAssertEqual(viewModel.eraseInteractionState, .hovering(first.id))
        XCTAssertEqual(viewModel.completedStrokes, [first, second])
        beginHandPinch(on: viewModel)
        XCTAssertEqual(viewModel.completedStrokes, [second])
        XCTAssertEqual(viewModel.eraseInteractionState, .idle)

        viewModel.updateSpatialFingertip(.tracking(CGPoint(x: 10, y: 0)))
        XCTAssertEqual(viewModel.completedStrokes, [second])
        endHandPinch(on: viewModel)
        XCTAssertEqual(viewModel.completedStrokes, [second])
        viewModel.undoLastStroke()
        XCTAssertEqual(viewModel.completedStrokes, [first, second])
        viewModel.redoLastStroke()
        XCTAssertEqual(viewModel.completedStrokes, [second])
    }

    func testEraseModePinchWithoutCandidateAndTrackingLossDoNotDelete() throws {
        let stroke = try makeStroke(startX: 0)
        let sessionService = ARSessionServiceSpy()
        let viewModel = makeViewModel(
            sessionService: sessionService,
            raycastService: SpatialRaycastServiceSpy(results: [makeRaycastResult(x: 1)]),
            project: try CanvasProject(name: "Safe Erase", strokes: [stroke])
        )
        viewModel.canvasDidAppear(isApplicationActive: true)
        sessionService.send(.trackingChanged(.normal))
        viewModel.selectTool(.erase)
        viewModel.updateSpatialFingertip(.tracking(.zero))
        beginHandPinch(on: viewModel)
        XCTAssertEqual(viewModel.completedStrokes, [stroke])

        sessionService.send(.trackingChanged(.limited(.insufficientFeatures)))
        XCTAssertEqual(viewModel.eraseInteractionState, .idle)
        XCTAssertEqual(viewModel.completedStrokes, [stroke])
    }

    func testHandHoverIsTransientAndDoesNotEnableDelete() throws {
        let original = try makeStroke(startX: 0)
        let sessionService = ARSessionServiceSpy()
        let renderer = StrokeRendererSpy()
        let viewModel = makeViewModel(
            sessionService: sessionService,
            raycastService: SpatialRaycastServiceSpy(results: [makeRaycastResult(x: 0.05)]),
            strokeRenderer: renderer,
            project: try CanvasProject(name: "Hover", strokes: [original])
        )
        viewModel.canvasDidAppear(isApplicationActive: true)
        sessionService.send(.trackingChanged(.normal))
        viewModel.selectTool(.select)
        viewModel.updateSpatialFingertip(.tracking(.zero))

        XCTAssertEqual(viewModel.handSelectionState, .hovering(original.id))
        XCTAssertNil(viewModel.selectedStrokeID)
        XCTAssertFalse(viewModel.canDeleteSelectedStroke)
        XCTAssertEqual(renderer.hoverUpdates.last, original.id)
    }

    func testHandSelectWithoutMovementThenDeleteUsesNormalPipeline() throws {
        let original = try makeStroke(startX: 0)
        let sessionService = ARSessionServiceSpy()
        let renderer = StrokeRendererSpy()
        let viewModel = makeViewModel(
            sessionService: sessionService,
            raycastService: SpatialRaycastServiceSpy(results: [makeRaycastResult(x: 0.05)]),
            strokeRenderer: renderer,
            project: try CanvasProject(name: "Delete", strokes: [original])
        )
        viewModel.canvasDidAppear(isApplicationActive: true)
        sessionService.send(.trackingChanged(.normal))
        viewModel.selectTool(.select)
        viewModel.updateSpatialFingertip(.tracking(.zero))
        beginHandPinch(on: viewModel)
        endHandPinch(on: viewModel)

        XCTAssertEqual(viewModel.selectedStrokeID, original.id)
        XCTAssertTrue(viewModel.canDeleteSelectedStroke)
        viewModel.deleteSelectedStroke()
        XCTAssertTrue(viewModel.completedStrokes.isEmpty)
        XCTAssertNil(viewModel.selectedStrokeID)
        viewModel.undoLastStroke()
        XCTAssertEqual(viewModel.completedStrokes, [original])
        viewModel.redoLastStroke()
        XCTAssertTrue(viewModel.completedStrokes.isEmpty)
    }

    func testMoveThenDeleteUndoRedoPreservesHistoryOrder() throws {
        let original = try makeStroke(startX: 0)
        let sessionService = ARSessionServiceSpy()
        let viewModel = makeViewModel(
            sessionService: sessionService,
            raycastService: SpatialRaycastServiceSpy(results: [makeRaycastResult(x: 0.05), makeRaycastResult(x: 0.25)]),
            project: try CanvasProject(name: "Move Delete", strokes: [original])
        )
        viewModel.canvasDidAppear(isApplicationActive: true)
        sessionService.send(.trackingChanged(.normal))
        viewModel.selectTool(.select)
        viewModel.updateSpatialFingertip(.tracking(.zero))
        beginHandPinch(on: viewModel)
        viewModel.updateSpatialFingertip(.tracking(CGPoint(x: 10, y: 0)))
        endHandPinch(on: viewModel)
        let moved = try XCTUnwrap(viewModel.completedStrokes.first)
        XCTAssertEqual(viewModel.selectedStrokeID, original.id)
        viewModel.deleteSelectedStroke()

        viewModel.undoLastStroke()
        XCTAssertEqual(viewModel.completedStrokes, [moved])
        viewModel.undoLastStroke()
        XCTAssertEqual(viewModel.completedStrokes, [original])
        viewModel.redoLastStroke()
        XCTAssertEqual(viewModel.completedStrokes, [moved])
        viewModel.redoLastStroke()
        XCTAssertTrue(viewModel.completedStrokes.isEmpty)
    }

    func testHandHoverGrabMoveCommitUndoRedoPreservesStrokeIdentityAndStyle() throws {
        let original = try makeStroke(startX: 0)
        let sessionService = ARSessionServiceSpy()
        let renderer = StrokeRendererSpy()
        let viewModel = makeViewModel(
            sessionService: sessionService,
            raycastService: SpatialRaycastServiceSpy(
                results: [makeRaycastResult(x: 0.05), makeRaycastResult(x: 0.25)]
            ),
            strokeRenderer: renderer,
            project: try CanvasProject(name: "Move Test", strokes: [original])
        )
        viewModel.canvasDidAppear(isApplicationActive: true)
        sessionService.send(.trackingChanged(.normal))
        viewModel.selectTool(.select)

        viewModel.updateSpatialFingertip(.tracking(.zero))
        XCTAssertEqual(viewModel.handSelectionState, .hovering(original.id))

        beginHandPinch(on: viewModel)
        guard case .grabbed(let strokeID, _, let snapshot, _) = viewModel.handSelectionState else {
            return XCTFail("Expected hovered stroke to be grabbed")
        }
        XCTAssertEqual(strokeID, original.id)
        XCTAssertEqual(snapshot, original)

        viewModel.updateSpatialFingertip(.tracking(CGPoint(x: 10, y: 0)))
        XCTAssertNotEqual(renderer.previewTranslations.last?.1, .zero)
        endHandPinch(on: viewModel)

        let moved = try XCTUnwrap(viewModel.completedStrokes.first)
        XCTAssertEqual(moved.id, original.id)
        XCTAssertEqual(moved.style, original.style)
        XCTAssertNotEqual(moved.points.map(\.position), original.points.map(\.position))
        XCTAssertEqual(viewModel.activeProject.strokes, [moved])
        XCTAssertTrue(viewModel.canUndo)

        viewModel.undoLastStroke()
        XCTAssertEqual(viewModel.completedStrokes, [original])
        viewModel.redoLastStroke()
        XCTAssertEqual(viewModel.completedStrokes, [moved])
    }

    func testPinchWithoutHoverDoesNotGrabOrMutateDocument() throws {
        let original = try makeStroke(startX: 0)
        let sessionService = ARSessionServiceSpy()
        let viewModel = makeViewModel(
            sessionService: sessionService,
            raycastService: SpatialRaycastServiceSpy(results: [makeRaycastResult(x: 1)]),
            project: try CanvasProject(name: "No Target", strokes: [original])
        )
        viewModel.canvasDidAppear(isApplicationActive: true)
        sessionService.send(.trackingChanged(.normal))
        viewModel.selectTool(.select)

        viewModel.updateSpatialFingertip(.tracking(.zero))
        XCTAssertEqual(viewModel.handSelectionState, .idle)
        beginHandPinch(on: viewModel)

        XCTAssertEqual(viewModel.handSelectionState, .idle)
        XCTAssertEqual(viewModel.completedStrokes, [original])
        XCTAssertFalse(viewModel.canUndo)
    }

    func testHandMoveCancellationRestoresOriginalForTrackingLossAndLifecycleReset() throws {
        let original = try makeStroke(startX: 0)
        let sessionService = ARSessionServiceSpy()
        let renderer = StrokeRendererSpy()
        let viewModel = makeViewModel(
            sessionService: sessionService,
            raycastService: SpatialRaycastServiceSpy(
                results: [makeRaycastResult(x: 0.05), makeRaycastResult(x: 0.25)]
            ),
            strokeRenderer: renderer,
            project: try CanvasProject(name: "Cancel Move", strokes: [original])
        )
        viewModel.canvasDidAppear(isApplicationActive: true)
        sessionService.send(.trackingChanged(.normal))
        viewModel.selectTool(.select)
        viewModel.updateSpatialFingertip(.tracking(.zero))
        beginHandPinch(on: viewModel)
        viewModel.updateSpatialFingertip(.tracking(CGPoint(x: 10, y: 0)))

        sessionService.send(.trackingChanged(.limited(.insufficientFeatures)))
        XCTAssertEqual(viewModel.handSelectionState, .idle)
        XCTAssertEqual(viewModel.completedStrokes, [original])
        XCTAssertEqual(renderer.previewTranslations.last?.1, .zero)
        XCTAssertFalse(viewModel.canUndo)

        sessionService.send(.trackingChanged(.normal))
        viewModel.applicationActivityDidChange(isActive: false)
        XCTAssertEqual(viewModel.handSelectionState, .idle)
        XCTAssertEqual(viewModel.completedStrokes, [original])
    }

    func testMovedStrokeRemainsTouchSelectableAndDeletable() throws {
        let original = try makeStroke(startX: 0)
        let sessionService = ARSessionServiceSpy()
        let renderer = StrokeRendererSpy()
        let viewModel = makeViewModel(
            sessionService: sessionService,
            raycastService: SpatialRaycastServiceSpy(
                results: [makeRaycastResult(x: 0.05), makeRaycastResult(x: 0.25)]
            ),
            strokeRenderer: renderer,
            project: try CanvasProject(name: "Delete Moved", strokes: [original])
        )
        viewModel.canvasDidAppear(isApplicationActive: true)
        sessionService.send(.trackingChanged(.normal))
        viewModel.selectTool(.select)
        viewModel.updateSpatialFingertip(.tracking(.zero))
        beginHandPinch(on: viewModel)
        viewModel.updateSpatialFingertip(.tracking(CGPoint(x: 10, y: 0)))
        endHandPinch(on: viewModel)
        let movedID = try XCTUnwrap(viewModel.completedStrokes.first?.id)

        renderer.nextHitStrokeID = movedID
        viewModel.selectionDidRequest(at: .zero)
        viewModel.deleteSelectedStroke()
        XCTAssertTrue(viewModel.completedStrokes.isEmpty)
        viewModel.undoLastStroke()
        XCTAssertEqual(viewModel.completedStrokes.first?.id, movedID)
    }

    private func makeViewModel(
        sessionService: ARSessionServiceSpy,
        raycastService: SpatialRaycastServiceSpy = SpatialRaycastServiceSpy(results: []),
        strokeRenderer: StrokeRendererSpy = StrokeRendererSpy(),
        history: CanvasHistory = CanvasHistory(),
        project: CanvasProject? = nil,
        relocalizationState: SpatialRelocalizationState = .none
    ) -> CanvasARViewModel {
        let project = project ?? makeProject()
        return CanvasARViewModel(
            sessionService: sessionService,
            raycastService: raycastService,
            drawingEngine: DrawingEngine(completedStrokes: project.strokes),
            strokeRenderer: strokeRenderer,
            brushSettings: .defaultSettings,
            project: project,
            repository: CanvasProjectRepositorySpy(),
            relocalizationState: relocalizationState,
            history: history
        )
    }

    private func makeHandDrawingViewModel(sessionService: ARSessionServiceSpy) -> CanvasARViewModel {
        let viewModel = makeViewModel(
            sessionService: sessionService,
            raycastService: SpatialRaycastServiceSpy(
                results: [
                    makeRaycastResult(x: 0), makeRaycastResult(x: 0.2), makeRaycastResult(x: 0.4),
                    makeRaycastResult(x: 0.6), makeRaycastResult(x: 0.8), makeRaycastResult(x: 1.0)
                ]
            )
        )
        viewModel.canvasDidAppear(isApplicationActive: true)
        sessionService.send(.trackingChanged(.normal))
        return viewModel
    }

    private func beginHandStroke(on viewModel: CanvasARViewModel, timestamp: TimeInterval = 0) {
        viewModel.updateSpatialFingertip(.tracking(.zero))
        viewModel.handTrackingDidUpdate(hand(distance: 0.08), timestamp: timestamp)
        viewModel.handTrackingDidUpdate(hand(distance: 0.08), timestamp: timestamp + 0.13)
    }

    private func beginHandPinch(on viewModel: CanvasARViewModel, timestamp: TimeInterval = 0) {
        viewModel.handTrackingDidUpdate(hand(distance: 0.08), timestamp: timestamp)
        viewModel.handTrackingDidUpdate(hand(distance: 0.08), timestamp: timestamp + 0.13)
    }

    private func endHandPinch(on viewModel: CanvasARViewModel, timestamp: TimeInterval = 0.2) {
        viewModel.handTrackingDidUpdate(hand(distance: 0.16), timestamp: timestamp)
        viewModel.handTrackingDidUpdate(hand(distance: 0.16), timestamp: timestamp + 0.13)
    }

    private func hand(distance: CGFloat) -> HandTrackingState {
        let index = HandLandmark(normalizedPosition: CGPoint(x: 0.5, y: 0.5), confidence: 1)!
        let thumb = HandLandmark(normalizedPosition: CGPoint(x: 0.5 + distance, y: 0.5), confidence: 1)!
        return .detected(HandPose(indexTip: index, thumbTip: thumb, wrist: nil))
    }

    private func makeProject() -> CanvasProject {
        do {
            return try CanvasProject(name: "Test Canvas")
        } catch {
            preconditionFailure("Test project construction failed: \(error)")
        }
    }

    private func makeStroke(startX: Float) throws -> Stroke {
        try Stroke(
            points: [
                try StrokePoint(position: CanvasPoint3D(x: startX, y: 0, z: 0), timestamp: 0),
                try StrokePoint(position: CanvasPoint3D(x: startX + 0.1, y: 0, z: 0), timestamp: 0.1)
            ],
            style: .defaultStyle,
            createdAt: Date(timeIntervalSinceReferenceDate: 1)
        )
    }

    private func makeRaycastResult(x: Float) -> SpatialRaycastResult {
        var transform = matrix_identity_float4x4
        transform.columns.3 = SIMD4(x, 0, 0, 1)
        return SpatialRaycastResult(worldTransform: transform, source: .existingPlaneGeometry)
    }

    private func drawStroke(
        with viewModel: CanvasARViewModel,
        start: CGPoint,
        end: CGPoint,
        timestamp: TimeInterval
    ) {
        viewModel.touchDidBegin(at: start, timestamp: timestamp)
        viewModel.touchDidMove(at: end, timestamp: timestamp + 0.1)
        viewModel.touchDidEnd(at: end, timestamp: timestamp + 0.1)
    }
}

@MainActor
private final class ARSessionServiceSpy: ARSessionControlling {
    private var eventHandler: (@MainActor (ARSessionEvent) -> Void)?
    private(set) var startCount = 0
    private(set) var pauseCount = 0
    private(set) var restartCount = 0

    func setEventHandler(_ handler: @escaping @MainActor (ARSessionEvent) -> Void) {
        eventHandler = handler
    }

    func start() {
        startCount += 1
        eventHandler?(.started)
    }

    func pause() {
        pauseCount += 1
        eventHandler?(.paused)
    }

    func restart() {
        restartCount += 1
        eventHandler?(.started)
    }

    func start(relocalizingWith initialWorldMap: ARWorldMap) {
        start()
    }

    func requestWorldMap() async throws -> ARWorldMap {
        throw SpatialWorldMapError.unavailable
    }

    func setCameraFrameHandler(_ handler: @escaping @Sendable (ARCameraFrame) -> Void) {}

    func send(_ event: ARSessionEvent) {
        eventHandler?(event)
    }
}

@MainActor
private final class SpatialRaycastServiceSpy: SpatialRaycasting {
    private(set) var requestedPoints: [CGPoint] = []
    private var results: [SpatialRaycastResult?]

    init(results: [SpatialRaycastResult?]) {
        self.results = results
    }

    func raycast(at screenPoint: CGPoint) -> SpatialRaycastResult? {
        requestedPoints.append(screenPoint)
        guard !results.isEmpty else {
            return nil
        }
        return results.removeFirst()
    }
}

@MainActor
private final class StrokeRendererSpy: StrokeRendering {
    private(set) var beginCount = 0
    private(set) var activePointUpdateCount = 0
    private(set) var beginStyles: [BrushStyle] = []
    private(set) var activePointStyles: [BrushStyle] = []
    private(set) var finalizedStrokes: [Stroke] = []
    private(set) var restoredStrokes: [Stroke] = []
    private(set) var completedStrokeIDs: [UUID] = []
    private(set) var removedStrokeIDs: [UUID] = []
    var nextHitStrokeID: UUID?
    private(set) var selectionUpdates: [UUID?] = []
    private(set) var hoverUpdates: [UUID?] = []
    private(set) var previewTranslations: [(UUID, SIMD3<Float>)] = []
    private(set) var clearCount = 0

    func beginActiveStroke(id: UUID, style: BrushStyle, firstPoint: StrokePoint) {
        beginCount += 1
        beginStyles.append(style)
    }

    func appendActiveStrokePoint(
        strokeID: UUID,
        from previousPoint: StrokePoint,
        to point: StrokePoint,
        style: BrushStyle
    ) {
        activePointUpdateCount += 1
        activePointStyles.append(style)
    }

    func finalizeStroke(_ stroke: Stroke) -> Bool {
        completedStrokeIDs.append(stroke.id)
        finalizedStrokes.append(stroke)
        return true
    }

    func renderStroke(_ stroke: Stroke) -> Bool {
        restoredStrokes.append(stroke)
        return true
    }

    func removeStroke(id: UUID) -> Bool {
        removedStrokeIDs.append(id)
        return true
    }

    func strokeID(at screenPoint: CGPoint) -> UUID? {
        nextHitStrokeID
    }

    func setSelectedStrokeID(_ strokeID: UUID?) -> Bool {
        selectionUpdates.append(strokeID)
        return true
    }

    func setHoveredStrokeID(_ strokeID: UUID?) -> Bool {
        hoverUpdates.append(strokeID)
        return true
    }

    func setStrokeTranslation(_ translation: SIMD3<Float>, for strokeID: UUID) -> Bool {
        previewTranslations.append((strokeID, translation))
        return true
    }

    func clear() {
        clearCount += 1
    }
}

private actor CanvasProjectRepositorySpy: CanvasProjectRepository {
    func createProject(named name: String) async throws -> CanvasProject {
        try CanvasProject(name: name)
    }

    func save(_ project: CanvasProject) async throws {}

    func loadProject(id: UUID) async throws -> CanvasProject {
        throw CanvasProjectRepositoryError.projectNotFound(id)
    }

    func listProjects() async throws -> [CanvasProjectSummary] {
        []
    }

    func renameProject(id: UUID, to name: String) async throws -> CanvasProject {
        throw CanvasProjectRepositoryError.projectNotFound(id)
    }

    func deleteProject(id: UUID) async throws {
        throw CanvasProjectRepositoryError.projectNotFound(id)
    }
}
