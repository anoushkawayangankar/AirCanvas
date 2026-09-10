import Foundation

/// Serializes saves and rejects an obsolete delayed autosave after a newer document revision was requested.
actor CanvasProjectSaveCoordinator {
    private let repository: any CanvasProjectRepository
    private var newestRevisionByProject: [UUID: Int] = [:]

    init(repository: any CanvasProjectRepository) {
        self.repository = repository
    }

    func save(_ project: CanvasProject, revision: Int) async throws -> CanvasProjectSaveDisposition {
        let newestRevision = newestRevisionByProject[project.id] ?? -1
        guard revision >= newestRevision else {
            AppLogger.persistence.debug("Discarded stale Canvas save request")
            return .discardedStale
        }

        newestRevisionByProject[project.id] = revision
        let startedAt = ProcessInfo.processInfo.systemUptime
        let disposition = try await repository.save(project, revision: revision)
#if DEBUG
        let duration = ProcessInfo.processInfo.systemUptime - startedAt
        AppLogger.performance.debug(
            "Autosave completed: revision=\(revision, privacy: .public), duration=\(duration, privacy: .public)s"
        )
#endif
        return disposition
    }
}
