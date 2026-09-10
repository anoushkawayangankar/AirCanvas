import Foundation

enum CanvasPersistenceWriteStage: Sendable {
    case beforePrimaryPublish
}

/// Actor-isolated local file storage. Each project is one atomically written, versioned JSON document.
actor FileCanvasProjectRepository: CanvasProjectRepository {
    private struct SchemaProbe: Decodable {
        let schemaVersion: Int
    }

    private struct StorageProbe: Decodable {
        let storageFormatVersion: Int?
    }

    private struct StoredCanvasDocument: Codable {
        static let currentStorageFormatVersion = 1

        let storageFormatVersion: Int
        let revision: Int
        let payloadByteCount: Int
        let checksum: String
        let project: CanvasProject

        init(project: CanvasProject, revision: Int) throws {
            guard revision >= 0 else { throw CanvasProjectRepositoryError.integrityValidationFailed }
            let payload = try Self.projectPayloadData(project)
            storageFormatVersion = Self.currentStorageFormatVersion
            self.revision = revision
            payloadByteCount = payload.count
            checksum = Self.checksum(for: payload)
            self.project = project
        }

        func validated() throws -> (project: CanvasProject, revision: Int) {
            guard storageFormatVersion == Self.currentStorageFormatVersion,
                  revision >= 0 else {
                throw CanvasProjectRepositoryError.integrityValidationFailed
            }
            let payload = try Self.projectPayloadData(project)
            guard payload.count == payloadByteCount,
                  Self.checksum(for: payload) == checksum else {
                throw CanvasProjectRepositoryError.integrityValidationFailed
            }
            return (project, revision)
        }

        private static func projectPayloadData(_ project: CanvasProject) throws -> Data {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            return try encoder.encode(project)
        }

        private static func checksum(for data: Data) -> String {
            var hash: UInt64 = 0xcbf29ce484222325
            for byte in data {
                hash ^= UInt64(byte)
                hash &*= 0x100000001b3
            }
            return String(hash, radix: 16)
        }
    }

    private let storageDirectory: URL
    private let writeFailureInjector: (@Sendable (CanvasPersistenceWriteStage) throws -> Void)?
    private var recoveryNotices: Set<UUID> = []

    init(
        storageDirectory: URL? = nil,
        writeFailureInjector: (@Sendable (CanvasPersistenceWriteStage) throws -> Void)? = nil
    ) {
        self.storageDirectory = storageDirectory ?? Self.defaultStorageDirectory()
        self.writeFailureInjector = writeFailureInjector
    }

    func createProject(named name: String) async throws -> CanvasProject {
        do {
            try ensureStorageDirectory()
            let now = Date.now
            let project = try CanvasProject(name: try uniqueName(for: name), createdAt: now, modifiedAt: now)
            try write(project, revision: 0)
            AppLogger.persistence.info("Created local Canvas project")
            return project
        } catch let error as CanvasProjectRepositoryError {
            throw error
        } catch {
            AppLogger.persistence.error("Unable to create local Canvas project: \(error.localizedDescription, privacy: .private(mask: .hash))")
            throw CanvasProjectRepositoryError.storageUnavailable
        }
    }

    func importProject(named name: String, strokes: [Stroke], sourceCreatedAt: Date) async throws -> CanvasProject {
        do {
            try ensureStorageDirectory()
            let now = Date.now
            let project = try CanvasProject(
                name: try uniqueName(for: name),
                createdAt: min(sourceCreatedAt, now),
                modifiedAt: now,
                strokes: strokes
            )
            try write(project, revision: 0)
            AppLogger.persistence.info("Imported local Canvas project")
            return project
        } catch let error as CanvasProjectRepositoryError {
            throw error
        } catch {
            AppLogger.persistence.error("Unable to import local Canvas project: \(error.localizedDescription, privacy: .private(mask: .hash))")
            throw CanvasProjectRepositoryError.storageUnavailable
        }
    }

    func save(_ project: CanvasProject) async throws {
        do {
            try write(project, revision: try nextRevision(for: project.id))
            AppLogger.persistence.debug("Saved local Canvas project")
        } catch let error as CanvasProjectRepositoryError {
            throw error
        } catch {
            AppLogger.persistence.error("Unable to save local Canvas project: \(error.localizedDescription, privacy: .private(mask: .hash))")
            throw CanvasProjectRepositoryError.storageUnavailable
        }
    }

    func save(_ project: CanvasProject, revision: Int) async throws -> CanvasProjectSaveDisposition {
        do {
            let newestPersistedRevision = try persistedRevision(for: project.id) ?? -1
            guard revision >= newestPersistedRevision else {
                AppLogger.persistence.debug("Discarded stale Canvas repository write")
                return .discardedStale
            }
            try write(project, revision: revision)
            AppLogger.persistence.debug("Persisted revisioned local Canvas project")
            return .persisted
        } catch let error as CanvasProjectRepositoryError {
            throw error
        } catch {
            AppLogger.persistence.error("Unable to persist revisioned Canvas project: \(error.localizedDescription, privacy: .private(mask: .hash))")
            throw CanvasProjectRepositoryError.storageUnavailable
        }
    }

    func loadProject(id: UUID) async throws -> CanvasProject {
        let fileURL = Self.projectFileURL(in: storageDirectory, id: id)
        let backupURL = Self.backupProjectFileURL(in: storageDirectory, id: id)

        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                return try readStoredProject(at: fileURL).project
            } catch let error as CanvasProjectRepositoryError where isUnsupportedSchema(error) {
                throw error
            } catch {
                AppLogger.persistence.error("Primary Canvas document failed validation; attempting recovery")
            }
        }

        guard FileManager.default.fileExists(atPath: backupURL.path) else {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                throw CanvasProjectRepositoryError.corruptedPrimary(id)
            }
            throw CanvasProjectRepositoryError.projectNotFound(id)
        }

        do {
            let recovered = try readStoredProject(at: backupURL)
            try atomicallyReplacePrimary(with: Data(contentsOf: backupURL), at: fileURL)
            recoveryNotices.insert(id)
            AppLogger.persistence.notice("Recovered Canvas document from last-known-good backup")
            return recovered.project
        } catch let error as CanvasProjectRepositoryError where isUnsupportedSchema(error) {
            throw error
        } catch {
            AppLogger.persistence.error("Canvas backup failed validation")
            throw CanvasProjectRepositoryError.corruptedBackup(id)
        }
    }

    func listProjects() async throws -> [CanvasProjectSummary] {
        do {
            try ensureStorageDirectory()
            let fileURLs = try FileManager.default.contentsOfDirectory(
                at: storageDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            var projects: [CanvasProject] = []
            for fileURL in fileURLs where fileURL.lastPathComponent.hasPrefix("project-") &&
                fileURL.pathExtension == "json" &&
                !fileURL.lastPathComponent.hasSuffix(".backup.json") {
                do {
                    projects.append(try await loadProject(id: Self.projectID(from: fileURL)))
                } catch {
                    AppLogger.persistence.error("Skipped damaged Canvas document during library reconciliation")
                }
            }

            return projects
                .map(CanvasProjectSummary.init(project:))
                .sorted { lhs, rhs in
                    if lhs.modifiedAt == rhs.modifiedAt {
                        return lhs.id.uuidString < rhs.id.uuidString
                    }
                    return lhs.modifiedAt > rhs.modifiedAt
                }
        } catch let error as CanvasProjectRepositoryError {
            throw error
        } catch {
            AppLogger.persistence.error("Unable to list local Canvas projects: \(error.localizedDescription, privacy: .private(mask: .hash))")
            throw CanvasProjectRepositoryError.storageUnavailable
        }
    }

    func renameProject(id: UUID, to name: String) async throws -> CanvasProject {
        let project = try await loadProject(id: id)
        let renamed = try project.renamed(to: uniqueName(for: name, excluding: id))
        try await save(renamed)
        return renamed
    }

    func duplicateProject(id: UUID) async throws -> CanvasProject {
        let source = try await loadProject(id: id)
        let now = Date.now
        var copiedSpatialState: SpatialCanvasState?
        if let sourceState = source.spatialState {
            let data = try await loadArchivedWorldMap(for: source)
            if let data {
                let state = try SpatialCanvasState(
                    mappingQuality: sourceState.mappingQuality,
                    updatedAt: now
                )
                try ensureStorageDirectory()
                try data.write(to: Self.worldMapFileURL(in: storageDirectory, identifier: state.mapIdentifier), options: .atomic)
                copiedSpatialState = state
            }
        }
        do {
            let duplicate = try CanvasProject(
                name: try uniqueName(for: "\(source.name) Copy"),
                createdAt: now,
                modifiedAt: now,
                strokes: source.strokes,
                spatialState: copiedSpatialState
            )
            try write(duplicate, revision: 0)
            return duplicate
        } catch {
            if let copiedSpatialState {
                try? FileManager.default.removeItem(at: Self.worldMapFileURL(in: storageDirectory, identifier: copiedSpatialState.mapIdentifier))
            }
            throw error
        }
    }

    func deleteProject(id: UUID) async throws {
        let fileURL = Self.projectFileURL(in: storageDirectory, id: id)
        let backupURL = Self.backupProjectFileURL(in: storageDirectory, id: id)
        guard FileManager.default.fileExists(atPath: fileURL.path) || FileManager.default.fileExists(atPath: backupURL.path) else {
            throw CanvasProjectRepositoryError.projectNotFound(id)
        }

        do {
            let project = try await loadProject(id: id)
            // Remove the recovery copy before the primary. A termination can therefore
            // leave either a valid primary or neither document, never a backup that
            // would unexpectedly resurrect a canvas after deletion was committed.
            try? FileManager.default.removeItem(at: backupURL)
            try FileManager.default.removeItem(at: fileURL)
            recoveryNotices.remove(id)
            if let spatialState = project.spatialState {
                let mapURL = Self.worldMapFileURL(in: storageDirectory, identifier: spatialState.mapIdentifier)
                do {
                    try FileManager.default.removeItem(at: mapURL)
                } catch where (error as NSError).code == NSFileNoSuchFileError {
                    // A missing map must not make an already-deleted project reappear.
                } catch {
                    AppLogger.persistence.error("Deleted project but could not remove its spatial reference: \(error.localizedDescription, privacy: .private(mask: .hash))")
                }
            }
            AppLogger.persistence.info("Deleted local Canvas project")
        } catch {
            AppLogger.persistence.error("Unable to delete local Canvas project: \(error.localizedDescription, privacy: .private(mask: .hash))")
            throw CanvasProjectRepositoryError.storageUnavailable
        }
    }

    func loadArchivedWorldMap(for project: CanvasProject) async throws -> Data? {
        guard let spatialState = project.spatialState else {
            return nil
        }
        let mapURL = Self.worldMapFileURL(in: storageDirectory, identifier: spatialState.mapIdentifier)
        guard FileManager.default.fileExists(atPath: mapURL.path) else {
            throw CanvasProjectRepositoryError.spatialStateUnavailable
        }
        do {
            return try Data(contentsOf: mapURL)
        } catch {
            AppLogger.persistence.error("Unable to read a spatial reference: \(error.localizedDescription, privacy: .private(mask: .hash))")
            throw CanvasProjectRepositoryError.invalidSpatialState
        }
    }

    func consumeRecoveryNotice(for id: UUID) async -> String? {
        guard recoveryNotices.remove(id) != nil else { return nil }
        return "AirCanvas restored this canvas from the last valid save."
    }

    func replaceSpatialState(
        for project: CanvasProject,
        archivedWorldMap: Data,
        state: SpatialCanvasState
    ) async throws -> CanvasProject {
        do {
            try ensureStorageDirectory()
            let newMapURL = Self.worldMapFileURL(in: storageDirectory, identifier: state.mapIdentifier)
            try archivedWorldMap.write(to: newMapURL, options: .atomic)

            let updatedProject = try project.replacingSpatialState(state)
            do {
            try write(updatedProject, revision: try nextRevision(for: updatedProject.id))
            } catch {
                try? FileManager.default.removeItem(at: newMapURL)
                throw error
            }

            if let oldState = project.spatialState, oldState.mapIdentifier != state.mapIdentifier {
                try? FileManager.default.removeItem(at: Self.worldMapFileURL(in: storageDirectory, identifier: oldState.mapIdentifier))
            }
            AppLogger.persistence.info("Replaced local Canvas spatial reference")
            return updatedProject
        } catch let error as CanvasProjectRepositoryError {
            throw error
        } catch {
            AppLogger.persistence.error("Unable to save a spatial reference: \(error.localizedDescription, privacy: .private(mask: .hash))")
            throw CanvasProjectRepositoryError.storageUnavailable
        }
    }

    nonisolated static func projectFileURL(in directory: URL, id: UUID) -> URL {
        directory.appending(path: "project-\(id.uuidString).json", directoryHint: .notDirectory)
    }

    nonisolated static func backupProjectFileURL(in directory: URL, id: UUID) -> URL {
        directory.appending(path: "project-\(id.uuidString).backup.json", directoryHint: .notDirectory)
    }

    nonisolated static func worldMapFileURL(in directory: URL, identifier: UUID) -> URL {
        directory
            .appending(path: "SpatialMaps", directoryHint: .isDirectory)
            .appending(path: "world-map-\(identifier.uuidString).archive", directoryHint: .notDirectory)
    }

    private static func defaultStorageDirectory() -> URL {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return applicationSupport
            .appending(path: "AirCanvas", directoryHint: .isDirectory)
            .appending(path: "Projects", directoryHint: .isDirectory)
    }

    private func write(_ project: CanvasProject, revision: Int) throws {
        try ensureStorageDirectory()
        let envelope = try StoredCanvasDocument(project: project, revision: revision)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(envelope)
        let primaryURL = Self.projectFileURL(in: storageDirectory, id: project.id)
        let backupURL = Self.backupProjectFileURL(in: storageDirectory, id: project.id)

        if FileManager.default.fileExists(atPath: primaryURL.path),
           let existingData = try? Data(contentsOf: primaryURL),
           (try? decodeStoredProject(from: existingData)) != nil {
            try atomicallyWrite(existingData, to: backupURL)
        }

        try writeFailureInjector?(.beforePrimaryPublish)
        try atomicallyReplacePrimary(with: data, at: primaryURL)
        applyFileProtection(to: primaryURL)
        if FileManager.default.fileExists(atPath: backupURL.path) {
            applyFileProtection(to: backupURL)
        }
    }

    private func persistedRevision(for id: UUID) throws -> Int? {
        let primaryURL = Self.projectFileURL(in: storageDirectory, id: id)
        guard FileManager.default.fileExists(atPath: primaryURL.path) else { return nil }
        return try? readStoredProject(at: primaryURL).revision
    }

    private func nextRevision(for id: UUID) throws -> Int {
        let persistedRevision = try persistedRevision(for: id)
        return (persistedRevision ?? -1) + 1
    }

    private func readStoredProject(at url: URL) throws -> (project: CanvasProject, revision: Int) {
        try decodeStoredProject(from: Data(contentsOf: url))
    }

    private func decodeStoredProject(from data: Data) throws -> (project: CanvasProject, revision: Int) {
        let decoder = JSONDecoder()
        let storageProbe = try? decoder.decode(StorageProbe.self, from: data)
        if storageProbe?.storageFormatVersion != nil {
            let envelope = try decoder.decode(StoredCanvasDocument.self, from: data)
            return try envelope.validated()
        }

        let probe = try decoder.decode(SchemaProbe.self, from: data)
        guard probe.schemaVersion == CanvasProject.currentSchemaVersion else {
            throw CanvasProjectRepositoryError.unsupportedSchemaVersion(probe.schemaVersion)
        }
        return (try decoder.decode(CanvasProject.self, from: data), 0)
    }

    private func atomicallyWrite(_ data: Data, to destinationURL: URL) throws {
        let temporaryURL = destinationURL
            .deletingLastPathComponent()
            .appending(path: ".\(destinationURL.lastPathComponent).\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        try data.write(to: temporaryURL, options: .atomic)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            _ = try FileManager.default.replaceItemAt(destinationURL, withItemAt: temporaryURL)
        } else {
            try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
        }
    }

    private func atomicallyReplacePrimary(with data: Data, at primaryURL: URL) throws {
        try atomicallyWrite(data, to: primaryURL)
    }

    private func applyFileProtection(to url: URL) {
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
    }

    private func isUnsupportedSchema(_ error: CanvasProjectRepositoryError) -> Bool {
        if case .unsupportedSchemaVersion = error { return true }
        return false
    }

    private func ensureStorageDirectory() throws {
        try FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: storageDirectory.appending(path: "SpatialMaps", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
    }

    private func uniqueName(for proposedName: String, excluding excludedID: UUID? = nil) throws -> String {
        let normalized = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw CanvasProjectValidationError.emptyName }
        let existingNames = try FileManager.default.contentsOfDirectory(at: storageDirectory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("project-") && $0.pathExtension == "json" }
            .filter { !$0.lastPathComponent.hasSuffix(".backup.json") }
            .filter { excludedID == nil || (try? Self.projectID(from: $0)) != excludedID }
            .compactMap { try? Data(contentsOf: $0) }
            .compactMap { try? decodeStoredProject(from: $0).project.name }
        guard existingNames.contains(normalized) else { return normalized }
        var suffix = 2
        while existingNames.contains("\(normalized) \(suffix)") { suffix += 1 }
        return "\(normalized) \(suffix)"
    }

    private nonisolated static func projectID(from fileURL: URL) throws -> UUID {
        let stem = fileURL.deletingPathExtension().lastPathComponent
        let identifier = String(stem.dropFirst("project-".count))
        guard let id = UUID(uuidString: identifier) else {
            throw CanvasProjectRepositoryError.invalidProjectData
        }
        return id
    }
}
