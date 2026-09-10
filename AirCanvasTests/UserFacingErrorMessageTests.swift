import XCTest
@testable import AirCanvas

final class UserFacingErrorMessageTests: XCTestCase {
    func testCanvasOpenUsesKnownRepositoryRecoveryMessage() {
        XCTAssertEqual(
            UserFacingErrorMessage.canvasOpen(CanvasProjectRepositoryError.projectNotFound(UUID())),
            "This canvas could not be found."
        )
    }

    func testExportUsesKnownDocumentRecoveryMessage() {
        XCTAssertEqual(
            UserFacingErrorMessage.export(AirCanvasDocumentError.unsupportedVersion(2)),
            "This AirCanvas document was created with a newer unsupported version."
        )
    }

    func testUnexpectedErrorsUseProductFacingFallbacks() {
        struct UnexpectedError: Error {}

        XCTAssertEqual(
            UserFacingErrorMessage.canvasOpen(UnexpectedError()),
            "AirCanvas could not open this canvas. Please try again."
        )
        XCTAssertEqual(
            UserFacingErrorMessage.export(UnexpectedError()),
            "AirCanvas could not prepare this export. Please try again."
        )
        XCTAssertEqual(
            UserFacingErrorMessage.library(UnexpectedError(), fallback: "The selected AirCanvas document could not be imported."),
            "The selected AirCanvas document could not be imported."
        )
    }
}
