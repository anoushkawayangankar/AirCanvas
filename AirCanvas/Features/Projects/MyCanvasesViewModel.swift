import Foundation
import Observation

enum MyCanvasesState: Equatable {
    case loading
    case loaded([CanvasProjectSummary])
    case failed(String)
}

@MainActor
@Observable
final class MyCanvasesViewModel {
    private let repository: any CanvasProjectRepository
    private var isLoading = false

    private(set) var state: MyCanvasesState = .loading
    private(set) var importErrorMessage: String?

    init(repository: any CanvasProjectRepository) {
        self.repository = repository
    }

    func refresh() async {
        guard !isLoading else {
            return
        }
        isLoading = true
        defer { isLoading = false }

        do {
            state = .loaded(try await repository.listProjects())
        } catch {
            AppLogger.persistence.error("Project library refresh failed: \(error.localizedDescription, privacy: .private(mask: .hash))")
            state = .failed(UserFacingErrorMessage.library(error, fallback: "AirCanvas could not load your canvases. Please try again."))
        }
    }

    func rename(_ project: CanvasProjectSummary, to name: String) async {
        do {
            _ = try await repository.renameProject(id: project.id, to: name)
            await refresh()
        } catch {
            AppLogger.persistence.error("Project rename failed: \(error.localizedDescription, privacy: .private(mask: .hash))")
            state = .failed(UserFacingErrorMessage.library(error, fallback: "AirCanvas could not rename this canvas. Please try again."))
        }
    }

    func duplicate(_ project: CanvasProjectSummary) async {
        do {
            _ = try await repository.duplicateProject(id: project.id)
            await refresh()
        } catch {
            state = .failed(UserFacingErrorMessage.library(error, fallback: "AirCanvas could not duplicate this canvas. Please try again."))
        }
    }

    func delete(_ project: CanvasProjectSummary) async {
        do {
            try await repository.deleteProject(id: project.id)
            await refresh()
        } catch {
            AppLogger.persistence.error("Project deletion failed: \(error.localizedDescription, privacy: .private(mask: .hash))")
            state = .failed(UserFacingErrorMessage.library(error, fallback: "AirCanvas could not delete this canvas. Please try again."))
        }
    }

    func importDocument(at url: URL) async {
        let accessedSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if accessedSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            let content = try AirCanvasDocumentImporter.importedContent(from: data)
            _ = try await repository.importProject(
                named: content.name,
                strokes: content.strokes,
                sourceCreatedAt: content.sourceCreatedAt
            )
            importErrorMessage = nil
            await refresh()
        } catch {
            AppLogger.persistence.error("Canvas document import failed: \(error.localizedDescription, privacy: .private(mask: .hash))")
            importErrorMessage = UserFacingErrorMessage.library(error, fallback: "The selected AirCanvas document could not be imported.")
        }
    }

    func dismissImportError() {
        importErrorMessage = nil
    }

    func recordImportError(_ error: Error) {
        importErrorMessage = UserFacingErrorMessage.library(error, fallback: "The selected AirCanvas document could not be imported.")
    }
}
