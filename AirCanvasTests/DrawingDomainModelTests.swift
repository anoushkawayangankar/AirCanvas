import XCTest
@testable import AirCanvas

final class DrawingDomainModelTests: XCTestCase {
    func testStrokePointRoundTripPreservesPositionAndTimestamp() throws {
        let point = try StrokePoint(
            position: CanvasPoint3D(x: 1.25, y: -0.5, z: 3.75),
            timestamp: 0.125
        )

        let decoded = try decode(StrokePoint.self, from: point)

        XCTAssertEqual(decoded, point)
    }

    func testBrushColorRoundTripPreservesRGBAComponents() throws {
        let color = try BrushColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 0.6)

        let decoded = try decode(BrushColor.self, from: color)

        XCTAssertEqual(decoded, color)
    }

    func testBrushStyleRejectsNonPositiveThickness() throws {
        let color = try BrushColor(red: 0, green: 0, blue: 0)

        XCTAssertThrowsError(try BrushStyle(color: color, thickness: 0)) { error in
            XCTAssertEqual(error as? BrushStyleValidationError, .invalidThickness)
        }
    }

    func testDefaultBrushSettingsAndOpaqueCanvasPaletteAreValidAndCodable() throws {
        XCTAssertGreaterThan(BrushSettings.defaultSettings.style.thickness, 0)

        for option in CanvasBrushConfiguration.colorOptions {
            XCTAssertEqual(option.color.alpha, 1)
            XCTAssertEqual(try decode(BrushColor.self, from: option.color), option.color)
        }

        XCTAssertEqual(
            try decode(BrushStyle.self, from: BrushSettings.defaultSettings.style),
            BrushSettings.defaultSettings.style
        )
    }

    func testStrokeRoundTripPreservesIDAndOrderedPoints() throws {
        let stroke = try makeStroke(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)

        let decoded = try decode(Stroke.self, from: stroke)

        XCTAssertEqual(decoded, stroke)
        XCTAssertEqual(decoded.id, stroke.id)
        XCTAssertEqual(decoded.points, stroke.points)
    }

    func testStrokeRejectsFewerThanTwoPoints() throws {
        let style = try makeStyle()
        let point = try StrokePoint(position: CanvasPoint3D(x: 0, y: 0, z: 0))

        XCTAssertThrowsError(try Stroke(points: [point], style: style)) { error in
            XCTAssertEqual(error as? StrokeValidationError, .insufficientPoints)
        }
    }

    func testCanvasProjectRoundTripPreservesIdentifiersTimestampsAndStrokeOrder() throws {
        let firstStroke = try makeStroke(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        let secondStroke = try makeStroke(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!)
        let createdAt = Date(timeIntervalSince1970: 1_000)
        let modifiedAt = Date(timeIntervalSince1970: 2_000)
        let project = try CanvasProject(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
            name: "  Studio sketch  ",
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            strokes: [firstStroke, secondStroke]
        )

        let decoded = try decode(CanvasProject.self, from: project)

        XCTAssertEqual(decoded, project)
        XCTAssertEqual(decoded.id, project.id)
        XCTAssertEqual(decoded.createdAt, createdAt)
        XCTAssertEqual(decoded.modifiedAt, modifiedAt)
        XCTAssertEqual(decoded.strokes.map(\.id), [firstStroke.id, secondStroke.id])
        XCTAssertEqual(decoded.name, "Studio sketch")
    }

    func testCanvasProjectRejectsAnUnsupportedSchemaVersion() {
        XCTAssertThrowsError(try CanvasProject(name: "Sketch", schemaVersion: 2)) { error in
            XCTAssertEqual(
                error as? CanvasProjectValidationError,
                .unsupportedSchemaVersion(2)
            )
        }
    }

    func testBrushSettingsChangesFutureStyleWithoutMutatingAnExistingSnapshot() throws {
        let originalStyle = try makeStyle()
        var settings = BrushSettings(style: originalStyle)
        let replacementColor = try BrushColor(red: 1, green: 0, blue: 0)

        try settings.update(color: replacementColor, thickness: 0.02)

        XCTAssertEqual(originalStyle.thickness, 0.01)
        XCTAssertEqual(settings.style.color, replacementColor)
        XCTAssertEqual(settings.style.thickness, 0.02)
    }

    private func makeStroke(id: UUID) throws -> Stroke {
        try Stroke(
            id: id,
            points: [
                StrokePoint(position: CanvasPoint3D(x: 0, y: 0, z: 0), timestamp: 0),
                StrokePoint(position: CanvasPoint3D(x: 1, y: 2, z: 3), timestamp: 0.1)
            ],
            style: makeStyle(),
            createdAt: Date(timeIntervalSince1970: 500)
        )
    }

    private func makeStyle() throws -> BrushStyle {
        try BrushStyle(
            color: BrushColor(red: 0.1, green: 0.2, blue: 0.3),
            thickness: 0.01
        )
    }

    private func decode<Value: Decodable>(_ type: Value.Type, from value: some Encodable) throws -> Value {
        try JSONDecoder().decode(Value.self, from: JSONEncoder().encode(value))
    }
}
