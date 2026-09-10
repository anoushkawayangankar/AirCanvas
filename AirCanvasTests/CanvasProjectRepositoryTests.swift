import Foundation
import XCTest
@testable import AirCanvas

final class CanvasProjectRepositoryTests: XCTestCase {
    private var storageDirectory: URL!
    private var repository: FileCanvasProjectRepository!

    override func setUpWithError() throws {
        storageDirectory = FileManager.default.temporaryDirectory
            .appending(path: "AirCanvasRepositoryTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        repository = FileCanvasProjectRepository(storageDirectory: storageDirectory)
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: storageDirectory.path) {
            try FileManager.default.removeItem(at: storageDirectory)
        }
        repository = nil
        storageDirectory = nil
    }

    func testCreateProjectPersistsStableIDAndAppearsInList() async throws {
        let project = try await repository.createProject(named: "  First Canvas  ")
        let projects = try await repository.listProjects()

        XCTAssertEqual(project.name, "First Canvas")
        XCTAssertEqual(projects.map(\.id), [project.id])
        XCTAssertEqual(projects[0].name, "First Canvas")
        XCTAssertEqual(projects[0].strokeCount, 0)
    }

    func testSaveAndLoadPreservesCompleteDomainProject() async throws {
        let project = try makeProject(name: "Saved Canvas", strokeOffsets: [0, 1])

        try await repository.save(project)
        let loaded = try await repository.loadProject(id: project.id)

        XCTAssertEqual(loaded.id, project.id)
        XCTAssertEqual(loaded.name, project.name)
        XCTAssertEqual(loaded.createdAt, project.createdAt)
        XCTAssertEqual(loaded.modifiedAt, project.modifiedAt)
        XCTAssertEqual(loaded.schemaVersion, CanvasProject.currentSchemaVersion)
        XCTAssertEqual(loaded.strokes.map(\.id), project.strokes.map(\.id))
        XCTAssertEqual(loaded.strokes.map(\.points), project.strokes.map(\.points))
        XCTAssertEqual(loaded.strokes.map(\.style), project.strokes.map(\.style))
    }

    func testStrokeAndPointOrderingCoordinatesAndStylesSurviveRoundTrip() async throws {
        let project = try makeProject(name: "Ordered", strokeOffsets: [2, 7, 11])

        try await repository.save(project)
        let loaded = try await repository.loadProject(id: project.id)

        XCTAssertEqual(loaded.strokes.map(\.id), project.strokes.map(\.id))
        for (loadedStroke, expectedStroke) in zip(loaded.strokes, project.strokes) {
            XCTAssertEqual(loadedStroke.points, expectedStroke.points)
            XCTAssertEqual(loadedStroke.style.color, expectedStroke.style.color)
            XCTAssertEqual(loadedStroke.style.thickness, expectedStroke.style.thickness, accuracy: 0.000_001)
        }
    }

    func testRenamePersistsAndUpdatesProjectMetadata() async throws {
        let project = try await repository.createProject(named: "Original")
        let renamed = try await repository.renameProject(id: project.id, to: "  Renamed Canvas ")
        let loaded = try await repository.loadProject(id: project.id)

        XCTAssertEqual(renamed.name, "Renamed Canvas")
        XCTAssertEqual(loaded.name, "Renamed Canvas")
        XCTAssertGreaterThanOrEqual(loaded.modifiedAt, project.modifiedAt)
    }

    func testCreateAndRenameNormalizeCollidingNamesWithoutChangingIdentity() async throws {
        let first = try await repository.createProject(named: "Untitled Canvas")
        let second = try await repository.createProject(named: "Untitled Canvas")
        let renamed = try await repository.renameProject(id: second.id, to: first.name)

        XCTAssertEqual(first.name, "Untitled Canvas")
        XCTAssertEqual(second.name, "Untitled Canvas 2")
        XCTAssertEqual(renamed.id, second.id)
        XCTAssertEqual(renamed.name, "Untitled Canvas 2")
    }

    func testDuplicateCreatesIndependentProjectWithCopiedContentAndSpatialState() async throws {
        let source = try makeProject(name: "Original", strokeOffsets: [0, 1])
        let sourceState = try SpatialCanvasState(mappingQuality: .mapped)
        let archivedMap = Data("source-world-map".utf8)
        let spatialSource = try await repository.replaceSpatialState(
            for: source,
            archivedWorldMap: archivedMap,
            state: sourceState
        )

        let duplicate = try await repository.duplicateProject(id: spatialSource.id)
        let duplicateMap = try await repository.loadArchivedWorldMap(for: duplicate)
        let updatedDuplicate = try duplicate.replacingStrokes([duplicate.strokes[0]])
        try await repository.save(updatedDuplicate)
        let reloadedSource = try await repository.loadProject(id: source.id)
        let listedProjects = try await repository.listProjects()

        XCTAssertNotEqual(duplicate.id, source.id)
        XCTAssertEqual(duplicate.name, "Original Copy")
        XCTAssertEqual(duplicate.strokes, source.strokes)
        XCTAssertNotEqual(duplicate.spatialState?.mapIdentifier, sourceState.mapIdentifier)
        XCTAssertEqual(duplicateMap, archivedMap)
        XCTAssertEqual(reloadedSource.strokes, source.strokes)
        XCTAssertEqual(listedProjects.count, 2)
    }

    func testSavingOrDeletingOneCanvasDoesNotModifyOtherCanvasDocuments() async throws {
        let canvasA = try makeProject(name: "A", strokeOffsets: [0])
        let canvasB = try makeProject(name: "B", strokeOffsets: [1])
        let canvasC = try makeProject(name: "C", strokeOffsets: [2])
        try await repository.save(canvasA)
        try await repository.save(canvasB)
        try await repository.save(canvasC)

        let updatedB = try canvasB.replacingStrokes([canvasB.strokes[0]])
        try await repository.save(updatedB)
        try await repository.deleteProject(id: canvasB.id)
        let loadedA = try await repository.loadProject(id: canvasA.id)
        let loadedC = try await repository.loadProject(id: canvasC.id)
        let remainingProjects = try await repository.listProjects()
        let remainingIDs = remainingProjects.map(\.id)

        XCTAssertEqual(loadedA, canvasA)
        XCTAssertEqual(loadedC, canvasC)
        XCTAssertEqual(remainingIDs.sorted { $0.uuidString < $1.uuidString }, [canvasA.id, canvasC.id].sorted { $0.uuidString < $1.uuidString })
    }

    func testDeleteRemovesProjectAndItsSingleStoredDocument() async throws {
        let project = try makeProject(name: "Delete Me", strokeOffsets: [0, 3])
        try await repository.save(project)
        let fileURL = FileCanvasProjectRepository.projectFileURL(in: storageDirectory, id: project.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        try await repository.deleteProject(id: project.id)

        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        let remainingProjects = try await repository.listProjects()
        XCTAssertTrue(remainingProjects.isEmpty)
        do {
            _ = try await repository.loadProject(id: project.id)
            XCTFail("Expected deleted project to be unavailable")
        } catch let error as CanvasProjectRepositoryError {
            XCTAssertEqual(error, .projectNotFound(project.id))
        }
    }

    func testProjectsListMostRecentlyModifiedFirst() async throws {
        let older = try makeProject(name: "Older", strokeOffsets: [0], modifiedAt: Date(timeIntervalSinceReferenceDate: 20))
        let newer = try makeProject(name: "Newer", strokeOffsets: [1], modifiedAt: Date(timeIntervalSinceReferenceDate: 30))
        try await repository.save(older)
        try await repository.save(newer)

        let listedProjects = try await repository.listProjects()
        XCTAssertEqual(listedProjects.map(\.id), [newer.id, older.id])
    }

    func testEmptyRepositoryReturnsNoProjects() async throws {
        let projects = try await repository.listProjects()
        XCTAssertTrue(projects.isEmpty)
    }

    func testUnsupportedSchemaIsRejectedExplicitly() async throws {
        let id = UUID()
        let data = Data("{\"schemaVersion\":2}".utf8)
        let fileURL = FileCanvasProjectRepository.projectFileURL(in: storageDirectory, id: id)
        try FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        try data.write(to: fileURL)

        do {
            _ = try await repository.loadProject(id: id)
            XCTFail("Expected unsupported schema rejection")
        } catch let error as CanvasProjectRepositoryError {
            XCTAssertEqual(error, .unsupportedSchemaVersion(2))
        }
    }

    func testSaveCoordinatorRejectsAnObsoleteSaveAfterNewerRevision() async throws {
        let recorder = ProjectSaveRecorder()
        let coordinator = CanvasProjectSaveCoordinator(repository: recorder)
        let oldProject = try makeProject(name: "Old", strokeOffsets: [0])
        let newProject = try oldProject.renamed(to: "New", modifiedAt: Date(timeIntervalSinceReferenceDate: 30))

        _ = try await coordinator.save(newProject, revision: 2)
        _ = try await coordinator.save(oldProject, revision: 1)

        let lastSavedProject = await recorder.lastSavedProject()
        XCTAssertEqual(lastSavedProject, newProject)
    }

    func testRepositoryRevisionRejectsStaleWriteAfterNewerRevisionPersists() async throws {
        let original = try makeProject(name: "Revisioned", strokeOffsets: [0])
        let newest = try original.renamed(to: "Newest", modifiedAt: Date(timeIntervalSinceReferenceDate: 30))

        let firstSave = try await repository.save(original, revision: 10)
        let newestSave = try await repository.save(newest, revision: 11)
        let staleSave = try await repository.save(original, revision: 10)
        let loaded = try await repository.loadProject(id: original.id)

        XCTAssertEqual(firstSave, .persisted)
        XCTAssertEqual(newestSave, .persisted)
        XCTAssertEqual(staleSave, .discardedStale)
        XCTAssertEqual(loaded, newest)
    }

    func testCorruptedPrimaryRecoversFromLastKnownGoodBackupAndReportsOnce() async throws {
        let original = try makeProject(name: "Recover", strokeOffsets: [0])
        let updated = try original.renamed(to: "Recover Updated", modifiedAt: Date(timeIntervalSinceReferenceDate: 30))
        try await repository.save(original)
        try await repository.save(updated)

        let primaryURL = FileCanvasProjectRepository.projectFileURL(in: storageDirectory, id: original.id)
        try Data("damaged".utf8).write(to: primaryURL, options: .atomic)

        let recoveredProject = try await repository.loadProject(id: original.id)
        let firstNotice = await repository.consumeRecoveryNotice(for: original.id)
        let secondNotice = await repository.consumeRecoveryNotice(for: original.id)
        let reloadedProject = try await repository.loadProject(id: original.id)

        XCTAssertEqual(recoveredProject, original)
        XCTAssertEqual(firstNotice, "AirCanvas restored this canvas from the last valid save.")
        XCTAssertNil(secondNotice)
        XCTAssertEqual(reloadedProject, original)
    }

    func testMissingPrimaryRecoversFromLastKnownGoodBackup() async throws {
        let original = try makeProject(name: "Recover Missing", strokeOffsets: [0])
        let updated = try original.renamed(to: "Updated", modifiedAt: Date(timeIntervalSinceReferenceDate: 30))
        try await repository.save(original)
        try await repository.save(updated)

        let primaryURL = FileCanvasProjectRepository.projectFileURL(in: storageDirectory, id: original.id)
        try FileManager.default.removeItem(at: primaryURL)

        let recoveredProject = try await repository.loadProject(id: original.id)
        XCTAssertEqual(recoveredProject, original)
    }

    func testValidPrimaryWinsOverOlderBackup() async throws {
        let original = try makeProject(name: "Primary Wins", strokeOffsets: [0])
        let updated = try original.renamed(to: "Newer", modifiedAt: Date(timeIntervalSinceReferenceDate: 30))
        try await repository.save(original)
        try await repository.save(updated)

        let loadedProject = try await repository.loadProject(id: original.id)
        XCTAssertEqual(loadedProject, updated)
    }

    func testCorruptedPrimaryAndBackupProducesControlledError() async throws {
        let project = try makeProject(name: "Both Damaged", strokeOffsets: [0])
        try await repository.save(project)
        try await repository.save(try project.renamed(to: "Updated", modifiedAt: Date(timeIntervalSinceReferenceDate: 30)))
        let primaryURL = FileCanvasProjectRepository.projectFileURL(in: storageDirectory, id: project.id)
        let backupURL = FileCanvasProjectRepository.backupProjectFileURL(in: storageDirectory, id: project.id)
        try Data("bad primary".utf8).write(to: primaryURL, options: .atomic)
        try Data("bad backup".utf8).write(to: backupURL, options: .atomic)

        do {
            _ = try await repository.loadProject(id: project.id)
            XCTFail("Expected a controlled backup corruption error")
        } catch let error as CanvasProjectRepositoryError {
            XCTAssertEqual(error, .corruptedBackup(project.id))
        }
    }

    func testFailedPublishPreservesExistingPrimaryDocument() async throws {
        let original = try makeProject(name: "Atomic", strokeOffsets: [0])
        try await repository.save(original)
        let updated = try original.renamed(to: "Should Not Publish", modifiedAt: Date(timeIntervalSinceReferenceDate: 30))
        let failingRepository = FileCanvasProjectRepository(storageDirectory: storageDirectory) { _ in
            throw InjectedPersistenceFailure.publish
        }

        do {
            _ = try await failingRepository.save(updated, revision: 1)
            XCTFail("Expected injected publish failure")
        } catch {
            // The primary must remain valid even though the new publish failed.
        }

        let loadedProject = try await repository.loadProject(id: original.id)
        XCTAssertEqual(loadedProject, original)
    }

    func testDamagedDocumentIsIsolatedFromProjectLibrary() async throws {
        let valid = try makeProject(name: "Valid", strokeOffsets: [0])
        try await repository.save(valid)
        let damagedID = UUID()
        let damagedURL = FileCanvasProjectRepository.projectFileURL(in: storageDirectory, id: damagedID)
        try Data("invalid document".utf8).write(to: damagedURL, options: .atomic)

        let projectIDs = try await repository.listProjects().map(\.id)
        XCTAssertEqual(projectIDs, [valid.id])
    }

    func testFailedDuplicateDoesNotPublishIncompleteProject() async throws {
        let original = try makeProject(name: "Original", strokeOffsets: [0])
        try await repository.save(original)
        let failingRepository = FileCanvasProjectRepository(storageDirectory: storageDirectory) { _ in
            throw InjectedPersistenceFailure.publish
        }

        do {
            _ = try await failingRepository.duplicateProject(id: original.id)
            XCTFail("Expected duplicate publication to fail")
        } catch {
            // Expected: staged duplicate is not published.
        }

        let projectIDs = try await repository.listProjects().map(\.id)
        XCTAssertEqual(projectIDs, [original.id])
    }

    func testFailedImportDoesNotPublishIncompleteProject() async throws {
        let source = try makeProject(name: "Import Source", strokeOffsets: [0])
        let failingRepository = FileCanvasProjectRepository(storageDirectory: storageDirectory) { _ in
            throw InjectedPersistenceFailure.publish
        }

        do {
            _ = try await failingRepository.importProject(
                named: source.name,
                strokes: source.strokes,
                sourceCreatedAt: source.createdAt
            )
            XCTFail("Expected import publication to fail")
        } catch {
            // Expected: no incomplete project directory is visible.
        }

        let projects = try await repository.listProjects()
        XCTAssertTrue(projects.isEmpty)
    }

    func testFinalUndoOrDeleteDocumentSnapshotCanBePersistedWithoutSelectionState() async throws {
        let original = try makeProject(name: "Document", strokeOffsets: [0, 1])
        let final = try original.replacingStrokes([original.strokes[0]], modifiedAt: Date(timeIntervalSinceReferenceDate: 40))

        try await repository.save(original)
        try await repository.save(final)
        let loaded = try await repository.loadProject(id: final.id)

        XCTAssertEqual(loaded.strokes, [original.strokes[0]])
        let persistedJSON = try String(decoding: JSONEncoder().encode(loaded), as: UTF8.self)
        XCTAssertFalse(persistedJSON.contains("selectedStrokeID"))
    }

    func testSpatialMetadataAndSeparateArchiveSurviveRoundTrip() async throws {
        let project = try makeProject(name: "Spatial", strokeOffsets: [0])
        let state = try SpatialCanvasState(mappingQuality: .mapped)
        let archive = Data("secure-world-map-test-data".utf8)

        let updated = try await repository.replaceSpatialState(
            for: project,
            archivedWorldMap: archive,
            state: state
        )
        let loaded = try await repository.loadProject(id: project.id)
        let loadedArchive = try await repository.loadArchivedWorldMap(for: loaded)

        XCTAssertEqual(updated.spatialState, state)
        XCTAssertEqual(loaded.spatialState, state)
        XCTAssertEqual(loadedArchive, archive)
        XCTAssertTrue(FileManager.default.fileExists(atPath: FileCanvasProjectRepository.worldMapFileURL(in: storageDirectory, identifier: state.mapIdentifier).path))
    }

    func testDeletingSpatialProjectRemovesItsSeparateArchive() async throws {
        let project = try makeProject(name: "Spatial Delete", strokeOffsets: [0])
        let state = try SpatialCanvasState(mappingQuality: .mapped)
        _ = try await repository.replaceSpatialState(
            for: project,
            archivedWorldMap: Data("world-map".utf8),
            state: state
        )
        let mapURL = FileCanvasProjectRepository.worldMapFileURL(in: storageDirectory, identifier: state.mapIdentifier)

        try await repository.deleteProject(id: project.id)

        XCTAssertFalse(FileManager.default.fileExists(atPath: mapURL.path))
    }

    func testProjectWithoutSpatialMetadataLoadsAsLegacyProject() async throws {
        let project = try makeProject(name: "Legacy", strokeOffsets: [0])
        try await repository.save(project)

        let loaded = try await repository.loadProject(id: project.id)

        XCTAssertNil(loaded.spatialState)
        let archive = try await repository.loadArchivedWorldMap(for: loaded)
        XCTAssertNil(archive)
    }

    private func makeProject(
        name: String,
        strokeOffsets: [Float],
        modifiedAt: Date = Date(timeIntervalSinceReferenceDate: 20)
    ) throws -> CanvasProject {
        let createdAt = Date(timeIntervalSinceReferenceDate: 10)
        let strokes = try strokeOffsets.enumerated().map { index, offset in
            let color = index.isMultiple(of: 2) ? BrushColor.canvasRed : BrushColor.canvasViolet
            let style = try BrushStyle(color: color, thickness: 0.004 + Float(index) * 0.003)
            return try Stroke(
                id: UUID(),
                points: [
                    try StrokePoint(position: CanvasPoint3D(x: offset, y: 0.1, z: -0.2), timestamp: 0),
                    try StrokePoint(position: CanvasPoint3D(x: offset + 0.2, y: 0.2, z: -0.3), timestamp: 0.4)
                ],
                style: style,
                createdAt: createdAt.addingTimeInterval(TimeInterval(index))
            )
        }
        return try CanvasProject(
            id: UUID(),
            name: name,
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            strokes: strokes
        )
    }
}

private actor ProjectSaveRecorder: CanvasProjectRepository {
    private var savedProject: CanvasProject?

    func createProject(named name: String) async throws -> CanvasProject {
        try CanvasProject(name: name)
    }

    func save(_ project: CanvasProject) async throws {
        savedProject = project
    }

    func loadProject(id: UUID) async throws -> CanvasProject {
        throw CanvasProjectRepositoryError.projectNotFound(id)
    }

    func listProjects() async throws -> [CanvasProjectSummary] { [] }

    func renameProject(id: UUID, to name: String) async throws -> CanvasProject {
        throw CanvasProjectRepositoryError.projectNotFound(id)
    }

    func deleteProject(id: UUID) async throws {
        throw CanvasProjectRepositoryError.projectNotFound(id)
    }

    func lastSavedProject() -> CanvasProject? {
        savedProject
    }
}

private enum InjectedPersistenceFailure: Error, Sendable {
    case publish
}
