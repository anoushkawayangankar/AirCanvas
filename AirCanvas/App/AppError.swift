enum AppError: Error, Equatable, Identifiable, Sendable {
    case operationUnavailable
    case operationFailed

    var id: String {
        switch self {
        case .operationUnavailable:
            "operationUnavailable"
        case .operationFailed:
            "operationFailed"
        }
    }

    var title: String {
        switch self {
        case .operationUnavailable:
            "This action is not available"
        case .operationFailed:
            "AirCanvas could not complete that action"
        }
    }

    var message: String {
        switch self {
        case .operationUnavailable:
            "Please try again when the required capability is available."
        case .operationFailed:
            "Please try again. If the problem continues, restart the app."
        }
    }

    var logDescription: String {
        switch self {
        case .operationUnavailable:
            "operation unavailable"
        case .operationFailed:
            "operation failed"
        }
    }
}
