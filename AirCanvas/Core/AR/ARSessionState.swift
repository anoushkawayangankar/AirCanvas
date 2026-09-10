enum ARSessionState: Equatable, Sendable {
    case idle
    case running(ARTrackingState)
    case interrupted
    case failed(ARSessionFailure)
}

enum ARSessionFailure: Equatable, Sendable {
    case sessionFailed

    var title: String {
        "AR Session Unavailable"
    }

    var message: String {
        "AirCanvas could not continue the spatial session. Try again, or return to Home and try later."
    }
}

enum ARSessionEvent: Equatable, Sendable {
    case started
    case paused
    case trackingChanged(ARTrackingState)
    case interrupted
    case interruptionEnded
    case mappingQualityChanged(SpatialMappingQuality)
    case failed(ARSessionFailure)
}

enum ARSessionStateReducer {
    static func state(after event: ARSessionEvent, from currentState: ARSessionState) -> ARSessionState {
        switch event {
        case .started, .interruptionEnded:
            .running(.initializing)
        case .paused:
            .idle
        case .trackingChanged(let trackingState):
            .running(trackingState)
        case .mappingQualityChanged:
            currentState
        case .interrupted:
            .interrupted
        case .failed(let failure):
            .failed(failure)
        }
    }
}
