import Observation

@MainActor
@Observable
final class AppState {
    let projectRepository: any CanvasProjectRepository
    var navigationPath: [AppRoute] = []
    var presentedError: AppError?

    init(projectRepository: any CanvasProjectRepository = FileCanvasProjectRepository()) {
        self.projectRepository = projectRepository
    }

    func present(_ error: AppError) {
        AppLogger.application.error("Presenting application error: \(error.logDescription, privacy: .public)")
        presentedError = error
    }

    func dismissError() {
        presentedError = nil
    }
}
