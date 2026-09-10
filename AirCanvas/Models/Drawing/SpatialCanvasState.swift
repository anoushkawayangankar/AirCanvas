import Foundation

/// Versioned, framework-independent metadata for a project's separately stored AR world map.
struct SpatialCanvasState: Codable, Equatable, Hashable, Sendable {
    static let currentVersion = 1

    let version: Int
    let mapIdentifier: UUID
    let mappingQuality: SpatialMappingQuality
    let updatedAt: Date

    init(
        version: Int = Self.currentVersion,
        mapIdentifier: UUID = UUID(),
        mappingQuality: SpatialMappingQuality,
        updatedAt: Date = .now
    ) throws {
        guard version == Self.currentVersion else {
            throw SpatialCanvasStateError.unsupportedVersion(version)
        }
        self.version = version
        self.mapIdentifier = mapIdentifier
        self.mappingQuality = mappingQuality
        self.updatedAt = updatedAt
    }
}

/// The durable, user-meaningful quality recorded when a world map was captured.
enum SpatialMappingQuality: String, Codable, Equatable, Hashable, Sendable {
    case unavailable
    case limited
    case extending
    case mapped

    var isSufficientForSpatialRestore: Bool {
        self == .mapped
    }
}

enum SpatialCanvasStateError: Error, Equatable, Sendable {
    case unsupportedVersion(Int)
}
