import XCTest
@testable import AirCanvas

@MainActor
final class AppStateTests: XCTestCase {
    func testPresentingAndDismissingErrorUpdatesPresentationState() {
        let state = AppState()

        state.present(.operationUnavailable)

        XCTAssertEqual(state.presentedError, .operationUnavailable)

        state.dismissError()

        XCTAssertNil(state.presentedError)
    }

    func testApplicationErrorsProvideDistinctUserFacingContent() {
        XCTAssertNotEqual(AppError.operationUnavailable.title, AppError.operationFailed.title)
        XCTAssertFalse(AppError.operationUnavailable.message.isEmpty)
        XCTAssertFalse(AppError.operationFailed.message.isEmpty)
    }
}
