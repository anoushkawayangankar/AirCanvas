import Foundation

/// Lightweight metadata used by the project library without exposing storage details to views.
struct CanvasProjectSummary: Equatable, Hashable, Sendable, Identifiable {
    let id: UUID
    let name: String
    let createdAt: Date
    let modifiedAt: Date
    let strokeCount: Int

    init(project: CanvasProject) {
        id = project.id
        name = project.name
        createdAt = project.createdAt
        modifiedAt = project.modifiedAt
        strokeCount = project.strokes.count
    }
}

enum CanvasProjectSaveDisposition: Equatable, Sendable {
    case persisted
    case discardedStale
}

enum CanvasProjectRepositoryError: Error, Equatable, Sendable, LocalizedError {
    case projectNotFound(UUID)
    case invalidProjectData
    case unsupportedSchemaVersion(Int)
    case storageUnavailable
    case spatialStateUnavailable
    case invalidSpatialState
    case corruptedPrimary(UUID)
    case corruptedBackup(UUID)
    case integrityValidationFailed
    case migrationFailed

    var errorDescription: String? {
        switch self {
        case .projectNotFound:
            "This canvas could not be found."
        case .invalidProjectData:
            "This canvas could not be read because its saved data is invalid."
        case .unsupportedSchemaVersion:
            "This canvas was created with an unsupported version of AirCanvas."
        case .storageUnavailable:
            "AirCanvas could not access local project storage."
        case .spatialStateUnavailable:
            "This canvas's spatial reference could not be found."
        case .invalidSpatialState:
            "This canvas's spatial reference could not be read."
        case .corruptedPrimary:
            "This canvas's latest saved version could not be read."
        case .corruptedBackup:
            "This canvas and its recovery copy could not be read."
        case .integrityValidationFailed:
            "This canvas failed an integrity check."
        case .migrationFailed:
            "This canvas could not be migrated safely."
        }
    }
}

/// The only persistence boundary used by project and Canvas features.
protocol CanvasProjectRepository: Sendable {
    func createProject(named name: String) async throws -> CanvasProject
    func importProject(named name: String, strokes: [Stroke], sourceCreatedAt: Date) async throws -> CanvasProject
    func save(_ project: CanvasProject) async throws
    func save(_ project: CanvasProject, revision: Int) async throws -> CanvasProjectSaveDisposition
    func loadProject(id: UUID) async throws -> CanvasProject
    func consumeRecoveryNotice(for id: UUID) async -> String?
    func listProjects() async throws -> [CanvasProjectSummary]
    func renameProject(id: UUID, to name: String) async throws -> CanvasProject
    func duplicateProject(id: UUID) async throws -> CanvasProject
    func deleteProject(id: UUID) async throws
    func loadArchivedWorldMap(for project: CanvasProject) async throws -> Data?
    func replaceSpatialState(
        for project: CanvasProject,
        archivedWorldMap: Data,
        state: SpatialCanvasState
    ) async throws -> CanvasProject
}

extension CanvasProjectRepository {
    func save(_ project: CanvasProject, revision: Int) async throws -> CanvasProjectSaveDisposition {
        try await save(project)
        return .persisted
    }

    func consumeRecoveryNotice(for id: UUID) async -> String? {
        nil
    }
    func importProject(named name: String, strokes: [Stroke], sourceCreatedAt: Date) async throws -> CanvasProject {
        throw CanvasProjectRepositoryError.storageUnavailable
    }

    func duplicateProject(id: UUID) async throws -> CanvasProject {
        throw CanvasProjectRepositoryError.storageUnavailable
    }
    func loadArchivedWorldMap(for project: CanvasProject) async throws -> Data? {
        nil
    }

    func replaceSpatialState(
        for project: CanvasProject,
        archivedWorldMap: Data,
        state: SpatialCanvasState
    ) async throws -> CanvasProject {
        throw CanvasProjectRepositoryError.spatialStateUnavailable
    }
}
