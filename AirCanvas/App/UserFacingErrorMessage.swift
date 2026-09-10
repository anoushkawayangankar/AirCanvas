import Foundation

/// Keeps recoverable presentation text concise and product-facing. Detailed
/// underlying errors remain available through the existing private OSLog paths.
enum UserFacingErrorMessage {
    static func canvasOpen(_ error: Error) -> String {
        message(
            for: error,
            fallback: "AirCanvas could not open this canvas. Please try again."
        )
    }

    static func export(_ error: Error) -> String {
        message(
            for: error,
            fallback: "AirCanvas could not prepare this export. Please try again."
        )
    }

    static func library(_ error: Error, fallback: String) -> String {
        message(for: error, fallback: fallback)
    }

    private static func message(for error: Error, fallback: String) -> String {
        switch error {
        case let repositoryError as CanvasProjectRepositoryError:
            return repositoryError.errorDescription ?? fallback
        case let documentError as AirCanvasDocumentError:
            return documentError.errorDescription ?? fallback
        default:
            return fallback
        }
    }
}
