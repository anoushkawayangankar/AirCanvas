import Foundation

/// The versioned, render-independent document model for an AirCanvas project.
struct CanvasProject: Codable, Equatable, Hashable, Sendable, Identifiable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let id: UUID
    let name: String
    let createdAt: Date
    let modifiedAt: Date
    let strokes: [Stroke]
    let spatialState: SpatialCanvasState?

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = .now,
        modifiedAt: Date = .now,
        strokes: [Stroke] = [],
        spatialState: SpatialCanvasState? = nil,
        schemaVersion: Int = CanvasProject.currentSchemaVersion
    ) throws {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else {
            throw CanvasProjectValidationError.emptyName
        }
        guard modifiedAt >= createdAt else {
            throw CanvasProjectValidationError.modifiedBeforeCreation
        }
        guard Set(strokes.map(\.id)).count == strokes.count else {
            throw CanvasProjectValidationError.duplicateStrokeIdentifier
        }
        guard schemaVersion == CanvasProject.currentSchemaVersion else {
            throw CanvasProjectValidationError.unsupportedSchemaVersion(schemaVersion)
        }

        self.schemaVersion = schemaVersion
        self.id = id
        self.name = normalizedName
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.strokes = strokes
        self.spatialState = spatialState
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(UUID.self, forKey: .id),
            name: container.decode(String.self, forKey: .name),
            createdAt: container.decode(Date.self, forKey: .createdAt),
            modifiedAt: container.decode(Date.self, forKey: .modifiedAt),
            strokes: container.decode([Stroke].self, forKey: .strokes),
            spatialState: try container.decodeIfPresent(SpatialCanvasState.self, forKey: .spatialState),
            schemaVersion: container.decode(Int.self, forKey: .schemaVersion)
        )
    }

    func renamed(to name: String, modifiedAt: Date = .now) throws -> CanvasProject {
        try CanvasProject(
            id: id,
            name: name,
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            strokes: strokes,
            spatialState: spatialState,
            schemaVersion: schemaVersion
        )
    }

    func replacingStrokes(_ strokes: [Stroke], modifiedAt: Date = .now) throws -> CanvasProject {
        try CanvasProject(
            id: id,
            name: name,
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            strokes: strokes,
            spatialState: spatialState,
            schemaVersion: schemaVersion
        )
    }

    func replacingSpatialState(_ spatialState: SpatialCanvasState?, modifiedAt: Date = .now) throws -> CanvasProject {
        try CanvasProject(
            id: id,
            name: name,
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            strokes: strokes,
            spatialState: spatialState,
            schemaVersion: schemaVersion
        )
    }
}

enum CanvasProjectValidationError: Error, Equatable, Sendable {
    case emptyName
    case modifiedBeforeCreation
    case duplicateStrokeIdentifier
    case unsupportedSchemaVersion(Int)
}
