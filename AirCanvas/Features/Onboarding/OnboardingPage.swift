struct OnboardingPage: Identifiable, Equatable {
    let id: String
    let symbolName: String
    let title: String
    let description: String

    static let all: [OnboardingPage] = [
        OnboardingPage(
            id: "spatialDrawing",
            symbolName: "scribble.variable",
            title: "Spatial Drawing",
            description: "AirCanvas is designed to let you create drawings within the physical space around you."
        ),
        OnboardingPage(
            id: "handInteraction",
            symbolName: "hand.draw",
            title: "Hand Interaction",
            description: "AirCanvas is designed to support hand and fingertip interaction, with touch controls available as an alternative. Hand tracking will be introduced in a future version."
        ),
        OnboardingPage(
            id: "privacy",
            symbolName: "hand.raised.fill",
            title: "Privacy",
            description: "When hand tracking is introduced, AirCanvas is planned to use Apple’s on-device Vision processing. Camera frames are not processed by this version of the app."
        ),
        OnboardingPage(
            id: "ready",
            symbolName: "checkmark.circle.fill",
            title: "Ready to Begin",
            description: "You are ready to explore AirCanvas. Spatial canvas tools will be introduced in a future milestone."
        )
    ]
}
