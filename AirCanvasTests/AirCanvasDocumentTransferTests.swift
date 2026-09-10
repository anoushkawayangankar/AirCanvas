import Foundation
import XCTest
@testable import AirCanvas

final class AirCanvasDocumentTransferTests: XCTestCase {
    private var storageDirectory: URL!
    private var repository: FileCanvasProjectRepository!

    override func setUpWithError() throws {
        storageDirectory = FileManager.default.temporaryDirectory
            .appending(path: "AirCanvasTransferTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        repository = FileCanvasProjectRepository(storageDirectory: storageDirectory)
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: storageDirectory.path) {
            try FileManager.default.removeItem(at: storageDirectory)
        }
        repository = nil
        storageDirectory = nil
    }

    func testEmptyCanvasEncodesAndDecodes() throws {
        let project = try CanvasProject(name: "Empty")
        let package = try AirCanvasDocumentImporter.decode(AirCanvasDocumentExporter.encodedData(for: project))

        XCTAssertEqual(package.canvasName, "Empty")
        XCTAssertTrue(package.strokes.isEmpty)
        XCTAssertNil(package.sourceReferencePoint)
        XCTAssertEqual(package.formatVersion, AirCanvasDocumentFormat.currentVersion)
    }

    func testNativeRoundTripPreservesPackageContentAndMetadata() throws {
        let project = try makeProject(name: "Artwork", offsets: [-2, 3])
        let package = try AirCanvasDocumentImporter.decode(AirCanvasDocumentExporter.encodedData(for: project))

        XCTAssertEqual(package.formatIdentifier, AirCanvasDocumentFormat.identifier)
        XCTAssertEqual(package.sourceCanvasID, project.id)
        XCTAssertEqual(package.canvasName, project.name)
        XCTAssertEqual(package.createdAt, project.createdAt)
        XCTAssertEqual(package.strokes, project.strokes)
        XCTAssertEqual(package.coordinateSpace, .arWorldReferenceV1)
        XCTAssertNotNil(package.sourceReferencePoint)
    }

    func testImportCreatesNewLocalCanvasIdentityAndPreservesRelativeArtwork() async throws {
        let original = try makeProject(name: "Original", offsets: [1, 4])
        try await repository.save(original)
        let data = try AirCanvasDocumentExporter.encodedData(for: original)
        let content = try AirCanvasDocumentImporter.importedContent(from: data)
        let imported = try await repository.importProject(
            named: content.name,
            strokes: content.strokes,
            sourceCreatedAt: content.sourceCreatedAt
        )
        let modifiedImported = try imported.replacingStrokes([imported.strokes[0]])
        try await repository.save(modifiedImported)
        let reloadedOriginal = try await repository.loadProject(id: original.id)

        XCTAssertNotEqual(imported.id, original.id)
        XCTAssertEqual(imported.strokes.map(\.id), original.strokes.map(\.id))
        XCTAssertEqual(relativeOffsets(imported.strokes), relativeOffsets(original.strokes))
        XCTAssertEqual(reloadedOriginal.strokes, original.strokes)
    }

    func testUnsupportedVersionIsRejected() throws {
        let data = try AirCanvasDocumentExporter.encodedData(for: try makeProject(name: "Version", offsets: [0]))
        var object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["formatVersion"] = AirCanvasDocumentFormat.currentVersion + 1
        let invalidData = try JSONSerialization.data(withJSONObject: object)

        XCTAssertThrowsError(try AirCanvasDocumentImporter.decode(invalidData)) { error in
            XCTAssertEqual(error as? AirCanvasDocumentError, .unsupportedVersion(2))
        }
    }

    func testMalformedAndDuplicateStrokeIdentifiersAreRejected() throws {
        XCTAssertThrowsError(try AirCanvasDocumentImporter.decode(Data("not-json".utf8)))

        let stroke = try makeStroke(offset: 0)
        XCTAssertThrowsError(
            try AirCanvasDocumentPackage(
                formatIdentifier: AirCanvasDocumentFormat.identifier,
                formatVersion: AirCanvasDocumentFormat.currentVersion,
                sourceCanvasID: UUID(),
                canvasName: "Duplicate IDs",
                createdAt: .now,
                exportedAt: .now,
                coordinateSpace: .arWorldReferenceV1,
                sourceReferencePoint: try CanvasPoint3D(x: 0, y: 0, z: 0),
                strokes: [stroke, stroke],
                metadata: [:]
            )
        ) { error in
            XCTAssertEqual(error as? AirCanvasDocumentError, .invalidDocument)
        }
    }

    func testNonFiniteJSONCoordinateTokensAreRejectedSafely() {
        let malformed = Data("{\"formatIdentifier\":\"com.aircanvas.document\",\"formatVersion\":1,\"strokes\":[{\"points\":[{\"position\":{\"x\":NaN}}]}]}".utf8)

        XCTAssertThrowsError(try AirCanvasDocumentImporter.decode(malformed)) { error in
            XCTAssertEqual(error as? AirCanvasDocumentError, .invalidDocument)
        }
    }

    func testResourceAndCoordinateLimitsAreRejected() throws {
        let stroke = try makeStroke(offset: 0)
        let tooManyStrokes = try (0...AirCanvasDocumentLimits.maximumStrokes).map { index in
            try Stroke(id: UUID(), points: stroke.points, style: stroke.style, createdAt: Date(timeIntervalSinceReferenceDate: TimeInterval(index)))
        }
        XCTAssertThrowsError(
            try AirCanvasDocumentPackage(
                formatIdentifier: AirCanvasDocumentFormat.identifier,
                formatVersion: AirCanvasDocumentFormat.currentVersion,
                sourceCanvasID: UUID(),
                canvasName: "Large",
                createdAt: .now,
                exportedAt: .now,
                coordinateSpace: .arWorldReferenceV1,
                sourceReferencePoint: try CanvasPoint3D(x: 0, y: 0, z: 0),
                strokes: tooManyStrokes,
                metadata: [:]
            )
        ) { error in
            XCTAssertEqual(error as? AirCanvasDocumentError, .resourceLimitExceeded)
        }
    }

    func testImageLayoutUsesStableDominantAxesPaddingAndTransformedGeometry() throws {
        let project = try makeProject(name: "Image", offsets: [-4, 4])
        let layout = CanvasImageExportLayout.make(for: project.strokes)

        XCTAssertEqual(layout.canvasSize, 2_048)
        XCTAssertEqual(layout.horizontalAxis, .x)
        // The fixture spans four units on Z and two on Y, so the deterministic
        // dominant-axis projection selects X then Z.
        XCTAssertEqual(layout.verticalAxis, .z)
        XCTAssertEqual(layout.strokes.count, project.strokes.count)
        XCTAssertTrue(layout.strokes.flatMap(\.points).allSatisfy { $0.x.isFinite && $0.y.isFinite })
        XCTAssertNotEqual(layout.strokes[0].points, layout.strokes[1].points)
    }

    func testEmptyArtworkUsesValidBlankImageLayout() {
        let layout = CanvasImageExportLayout.make(for: [])

        XCTAssertEqual(layout.canvasSize, 2_048)
        XCTAssertTrue(layout.strokes.isEmpty)
        XCTAssertEqual(layout.horizontalAxis, .x)
        XCTAssertEqual(layout.verticalAxis, .y)
    }

    @MainActor
    func testPNGExportProducesArtworkOnlyImageData() throws {
        let project = try makeProject(name: "PNG", offsets: [0])
        let data = try CanvasImageExporter.pngData(for: project)

        XCTAssertGreaterThan(data.count, 8)
        XCTAssertEqual(Array(data.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
    }

    func testImportingMultipleExportsCreatesIndependentCanvasDocuments() async throws {
        let canvasA = try makeProject(name: "A", offsets: [0])
        let canvasB = try makeProject(name: "B", offsets: [10])
        let importedA = try AirCanvasDocumentImporter.importedContent(from: AirCanvasDocumentExporter.encodedData(for: canvasA))
        let importedB = try AirCanvasDocumentImporter.importedContent(from: AirCanvasDocumentExporter.encodedData(for: canvasB))
        let localA = try await repository.importProject(named: importedA.name, strokes: importedA.strokes, sourceCreatedAt: importedA.sourceCreatedAt)
        let localB = try await repository.importProject(named: importedB.name, strokes: importedB.strokes, sourceCreatedAt: importedB.sourceCreatedAt)
        let editedB = try localB.replacingStrokes([localB.strokes[0]])
        try await repository.save(editedB)
        let reloadedA = try await repository.loadProject(id: localA.id)
        let reloadedB = try await repository.loadProject(id: localB.id)

        XCTAssertNotEqual(localA.id, localB.id)
        XCTAssertEqual(reloadedA, localA)
        XCTAssertEqual(reloadedB, editedB)
    }

    func testExportContainsLatestProvidedProjectSnapshotWithoutHistory() throws {
        let original = try makeProject(name: "Latest", offsets: [0])
        let latest = try original.replacingStrokes([try makeStroke(offset: 10)])
        let data = try AirCanvasDocumentExporter.encodedData(for: latest)
        let package = try AirCanvasDocumentImporter.decode(data)
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertEqual(package.strokes, latest.strokes)
        XCTAssertFalse(text.contains("selectedStrokeID"))
        XCTAssertFalse(text.contains("history"))
    }

    private func makeProject(name: String, offsets: [Float]) throws -> CanvasProject {
        try CanvasProject(
            id: UUID(),
            name: name,
            createdAt: Date(timeIntervalSinceReferenceDate: 10),
            modifiedAt: Date(timeIntervalSinceReferenceDate: 20),
            strokes: try offsets.map(makeStroke(offset:))
        )
    }

    private func makeStroke(offset: Float) throws -> Stroke {
        try Stroke(
            id: UUID(),
            points: [
                try StrokePoint(position: CanvasPoint3D(x: offset, y: -1, z: 2), timestamp: 0),
                try StrokePoint(position: CanvasPoint3D(x: offset + 0.5, y: 1, z: -2), timestamp: 0.2)
            ],
            style: try BrushStyle(color: .canvasViolet, thickness: 0.01),
            createdAt: Date(timeIntervalSinceReferenceDate: 12)
        )
    }

    private func relativeOffsets(_ strokes: [Stroke]) -> [CanvasPoint3D] {
        let points = strokes.flatMap(\.points).map(\.position)
        guard let first = points.first else { return [] }
        return points.map { point in
            try! CanvasPoint3D(x: point.x - first.x, y: point.y - first.y, z: point.z - first.z)
        }
    }
}
