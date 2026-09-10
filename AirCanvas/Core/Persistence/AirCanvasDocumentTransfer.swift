import Foundation
import UIKit
import UniformTypeIdentifiers

extension UTType {
    static let airCanvasDocument = UTType(exportedAs: "com.aircanvas.document", conformingTo: .data)
}

enum AirCanvasDocumentFormat {
    static let identifier = "com.aircanvas.document"
    static let currentVersion = 1
    static let fileExtension = "aircanvas"
}

enum AirCanvasDocumentCoordinateSpace: String, Codable, Sendable {
    /// Points remain in source AR-world axes. `sourceReferencePoint` makes their
    /// relative geometry portable without exporting a room-bound ARWorldMap.
    case arWorldReferenceV1
}

enum AirCanvasDocumentLimits {
    static let maximumFileBytes = 25 * 1_024 * 1_024
    static let maximumStrokes = 10_000
    static let maximumPointsPerStroke = 1_024
    static let maximumTotalPoints = 200_000
    static let maximumNameLength = 120
    static let maximumMetadataEntries = 16
    static let maximumMetadataValueLength = 256
    static let maximumCoordinateMagnitude: Float = 10_000
    static let maximumStrokeThickness: Float = 0.1
}

enum AirCanvasDocumentError: Error, Equatable, Sendable, LocalizedError {
    case fileTooLarge
    case unsupportedFormat
    case unsupportedVersion(Int)
    case invalidDocument
    case resourceLimitExceeded
    case invalidGeometry
    case unableToWriteExport

    var errorDescription: String? {
        switch self {
        case .fileTooLarge:
            "This AirCanvas document is too large to import."
        case .unsupportedFormat:
            "This file is not an AirCanvas document."
        case .unsupportedVersion:
            "This AirCanvas document was created with a newer unsupported version."
        case .invalidDocument, .invalidGeometry:
            "This AirCanvas document is invalid."
        case .resourceLimitExceeded:
            "This AirCanvas document exceeds supported content limits."
        case .unableToWriteExport:
            "AirCanvas could not prepare the export file."
        }
    }
}

/// Portable, versioned content only. Runtime selection, history, local file paths,
/// and the source environment's ARWorldMap are deliberately excluded.
struct AirCanvasDocumentPackage: Codable, Equatable, Sendable {
    let formatIdentifier: String
    let formatVersion: Int
    let sourceCanvasID: UUID
    let canvasName: String
    let createdAt: Date
    let exportedAt: Date
    let coordinateSpace: AirCanvasDocumentCoordinateSpace
    let sourceReferencePoint: CanvasPoint3D?
    let strokes: [Stroke]
    let metadata: [String: String]

    init(
        project: CanvasProject,
        exportedAt: Date = .now,
        metadata: [String: String] = [:]
    ) throws {
        try self.init(
            formatIdentifier: AirCanvasDocumentFormat.identifier,
            formatVersion: AirCanvasDocumentFormat.currentVersion,
            sourceCanvasID: project.id,
            canvasName: project.name,
            createdAt: project.createdAt,
            exportedAt: exportedAt,
            coordinateSpace: .arWorldReferenceV1,
            sourceReferencePoint: try Self.centroid(of: project.strokes),
            strokes: project.strokes,
            metadata: metadata
        )
    }

    init(
        formatIdentifier: String,
        formatVersion: Int,
        sourceCanvasID: UUID,
        canvasName: String,
        createdAt: Date,
        exportedAt: Date,
        coordinateSpace: AirCanvasDocumentCoordinateSpace,
        sourceReferencePoint: CanvasPoint3D?,
        strokes: [Stroke],
        metadata: [String: String]
    ) throws {
        guard formatIdentifier == AirCanvasDocumentFormat.identifier else {
            throw AirCanvasDocumentError.unsupportedFormat
        }
        guard formatVersion == AirCanvasDocumentFormat.currentVersion else {
            throw AirCanvasDocumentError.unsupportedVersion(formatVersion)
        }
        let normalizedName = canvasName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty, normalizedName.count <= AirCanvasDocumentLimits.maximumNameLength else {
            throw AirCanvasDocumentError.invalidDocument
        }
        guard createdAt.timeIntervalSinceReferenceDate.isFinite,
              exportedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw AirCanvasDocumentError.invalidDocument
        }
        guard metadata.count <= AirCanvasDocumentLimits.maximumMetadataEntries,
              metadata.allSatisfy({ $0.key.count <= AirCanvasDocumentLimits.maximumMetadataValueLength && $0.value.count <= AirCanvasDocumentLimits.maximumMetadataValueLength }) else {
            throw AirCanvasDocumentError.resourceLimitExceeded
        }

        try Self.validate(strokes: strokes, referencePoint: sourceReferencePoint)
        self.formatIdentifier = formatIdentifier
        self.formatVersion = formatVersion
        self.sourceCanvasID = sourceCanvasID
        self.canvasName = normalizedName
        self.createdAt = createdAt
        self.exportedAt = exportedAt
        self.coordinateSpace = coordinateSpace
        self.sourceReferencePoint = sourceReferencePoint
        self.strokes = strokes
        self.metadata = metadata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            formatIdentifier: container.decode(String.self, forKey: .formatIdentifier),
            formatVersion: container.decode(Int.self, forKey: .formatVersion),
            sourceCanvasID: container.decode(UUID.self, forKey: .sourceCanvasID),
            canvasName: container.decode(String.self, forKey: .canvasName),
            createdAt: container.decode(Date.self, forKey: .createdAt),
            exportedAt: container.decode(Date.self, forKey: .exportedAt),
            coordinateSpace: container.decode(AirCanvasDocumentCoordinateSpace.self, forKey: .coordinateSpace),
            sourceReferencePoint: try container.decodeIfPresent(CanvasPoint3D.self, forKey: .sourceReferencePoint),
            strokes: container.decode([Stroke].self, forKey: .strokes),
            metadata: try container.decodeIfPresent([String: String].self, forKey: .metadata) ?? [:]
        )
    }

    /// A fresh AR session gets a deterministic, visible local reference rather
    /// than incorrectly treating the source room's world origin as meaningful.
    func importedStrokes() throws -> [Stroke] {
        guard !strokes.isEmpty else { return [] }
        guard let sourceReferencePoint else { throw AirCanvasDocumentError.invalidGeometry }
        let target = try CanvasPoint3D(x: 0, y: -0.2, z: -1.0)
        let dx = target.x - sourceReferencePoint.x
        let dy = target.y - sourceReferencePoint.y
        let dz = target.z - sourceReferencePoint.z

        return try strokes.map { stroke in
            let points = try stroke.points.map { point in
                try StrokePoint(
                    position: CanvasPoint3D(
                        x: point.position.x + dx,
                        y: point.position.y + dy,
                        z: point.position.z + dz
                    ),
                    timestamp: point.timestamp
                )
            }
            return try Stroke(id: stroke.id, points: points, style: stroke.style, createdAt: stroke.createdAt)
        }
    }

    private static func validate(strokes: [Stroke], referencePoint: CanvasPoint3D?) throws {
        guard strokes.count <= AirCanvasDocumentLimits.maximumStrokes else {
            throw AirCanvasDocumentError.resourceLimitExceeded
        }
        guard Set(strokes.map(\.id)).count == strokes.count else {
            throw AirCanvasDocumentError.invalidDocument
        }
        let pointCount = strokes.reduce(0) { $0 + $1.points.count }
        guard pointCount <= AirCanvasDocumentLimits.maximumTotalPoints,
              strokes.allSatisfy({ $0.points.count >= 2 && $0.points.count <= AirCanvasDocumentLimits.maximumPointsPerStroke }) else {
            throw AirCanvasDocumentError.resourceLimitExceeded
        }
        guard strokes.allSatisfy({ stroke in
            stroke.style.thickness <= AirCanvasDocumentLimits.maximumStrokeThickness &&
                stroke.points.allSatisfy { point in
                    abs(point.position.x) <= AirCanvasDocumentLimits.maximumCoordinateMagnitude &&
                        abs(point.position.y) <= AirCanvasDocumentLimits.maximumCoordinateMagnitude &&
                        abs(point.position.z) <= AirCanvasDocumentLimits.maximumCoordinateMagnitude
                }
        }) else {
            throw AirCanvasDocumentError.invalidGeometry
        }
        if strokes.isEmpty {
            guard referencePoint == nil else { throw AirCanvasDocumentError.invalidDocument }
        } else {
            guard referencePoint != nil else { throw AirCanvasDocumentError.invalidGeometry }
        }
    }

    private static func centroid(of strokes: [Stroke]) throws -> CanvasPoint3D? {
        let points = strokes.flatMap(\.points)
        guard !points.isEmpty else { return nil }
        let count = Double(points.count)
        let x = points.reduce(0.0) { $0 + Double($1.position.x) } / count
        let y = points.reduce(0.0) { $0 + Double($1.position.y) } / count
        let z = points.reduce(0.0) { $0 + Double($1.position.z) } / count
        guard x.isFinite, y.isFinite, z.isFinite else { throw AirCanvasDocumentError.invalidGeometry }
        return try CanvasPoint3D(x: Float(x), y: Float(y), z: Float(z))
    }
}

enum AirCanvasDocumentExporter {
    static func encodedData(for project: CanvasProject) throws -> Data {
        let package = try AirCanvasDocumentPackage(project: project)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let data = try encoder.encode(package)
        guard data.count <= AirCanvasDocumentLimits.maximumFileBytes else {
            throw AirCanvasDocumentError.fileTooLarge
        }
        return data
    }

    static func writeTemporaryDocument(for project: CanvasProject) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "AirCanvasExports", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let fileURL = directory.appending(path: "\(UUID().uuidString).\(AirCanvasDocumentFormat.fileExtension)")
            try encodedData(for: project).write(to: fileURL, options: .atomic)
            return fileURL
        } catch let error as AirCanvasDocumentError {
            throw error
        } catch {
            throw AirCanvasDocumentError.unableToWriteExport
        }
    }

    static func removeTemporaryDocument(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}

enum AirCanvasDocumentImporter {
    static func decode(_ data: Data) throws -> AirCanvasDocumentPackage {
        guard data.count <= AirCanvasDocumentLimits.maximumFileBytes else {
            throw AirCanvasDocumentError.fileTooLarge
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        do {
            return try decoder.decode(AirCanvasDocumentPackage.self, from: data)
        } catch let error as AirCanvasDocumentError {
            throw error
        } catch {
            throw AirCanvasDocumentError.invalidDocument
        }
    }

    static func importedContent(from data: Data) throws -> ImportedAirCanvasContent {
        let package = try decode(data)
        return ImportedAirCanvasContent(
            name: package.canvasName,
            sourceCreatedAt: package.createdAt,
            strokes: try package.importedStrokes()
        )
    }
}

struct ImportedAirCanvasContent: Sendable {
    let name: String
    let sourceCreatedAt: Date
    let strokes: [Stroke]
}

enum CanvasImageProjectionAxis: Int, CaseIterable, Sendable {
    case x
    case y
    case z

    func value(of point: CanvasPoint3D) -> Float {
        switch self {
        case .x: point.x
        case .y: point.y
        case .z: point.z
        }
    }
}

struct CanvasImageExportLayout: Sendable {
    struct Point: Sendable, Equatable {
        let x: Float
        let y: Float
    }

    struct StrokeLayout: Sendable {
        let points: [Point]
        let style: BrushStyle
    }

    let horizontalAxis: CanvasImageProjectionAxis
    let verticalAxis: CanvasImageProjectionAxis
    let canvasSize: Float
    let strokes: [StrokeLayout]

    static func make(for strokes: [Stroke], resolution: Int = 2_048, paddingFraction: Float = 0.08) -> CanvasImageExportLayout {
        let allPoints = strokes.flatMap(\.points).map(\.position)
        guard !allPoints.isEmpty else {
            return CanvasImageExportLayout(horizontalAxis: .x, verticalAxis: .y, canvasSize: Float(resolution), strokes: [])
        }
        let axes = CanvasImageProjectionAxis.allCases.sorted { lhs, rhs in
            let lhsRange = range(of: lhs, in: allPoints)
            let rhsRange = range(of: rhs, in: allPoints)
            return lhsRange == rhsRange ? lhs.rawValue < rhs.rawValue : lhsRange > rhsRange
        }
        let horizontal = axes[0]
        let vertical = axes[1]
        let minHorizontal = allPoints.map { horizontal.value(of: $0) }.min() ?? 0
        let maxHorizontal = allPoints.map { horizontal.value(of: $0) }.max() ?? 0
        let minVertical = allPoints.map { vertical.value(of: $0) }.min() ?? 0
        let maxVertical = allPoints.map { vertical.value(of: $0) }.max() ?? 0
        let extent = max(maxHorizontal - minHorizontal, maxVertical - minVertical, 0.05)
        let usableSize = Float(resolution) * (1 - 2 * paddingFraction)
        let scale = usableSize / extent
        let horizontalCenter = (minHorizontal + maxHorizontal) / 2
        let verticalCenter = (minVertical + maxVertical) / 2
        let imageCenter = Float(resolution) / 2

        return CanvasImageExportLayout(
            horizontalAxis: horizontal,
            verticalAxis: vertical,
            canvasSize: Float(resolution),
            strokes: strokes.map { stroke in
                StrokeLayout(
                    points: stroke.points.map { point in
                        Point(
                            x: imageCenter + (horizontal.value(of: point.position) - horizontalCenter) * scale,
                            y: imageCenter - (vertical.value(of: point.position) - verticalCenter) * scale
                        )
                    },
                    style: stroke.style
                )
            }
        )
    }

    private static func range(of axis: CanvasImageProjectionAxis, in points: [CanvasPoint3D]) -> Float {
        let values = points.map { axis.value(of: $0) }
        return (values.max() ?? 0) - (values.min() ?? 0)
    }
}

enum CanvasImageExporter {
    static let resolution = 2_048

    @MainActor
    static func pngData(for project: CanvasProject) throws -> Data {
        let layout = CanvasImageExportLayout.make(for: project.strokes, resolution: resolution)
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: CGFloat(layout.canvasSize), height: CGFloat(layout.canvasSize)),
            format: UIGraphicsImageRendererFormat()
        )
        let data = renderer.pngData { context in
            let cg = context.cgContext
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            for stroke in layout.strokes {
                guard let first = stroke.points.first else { continue }
                let path = UIBezierPath()
                path.move(to: CGPoint(x: CGFloat(first.x), y: CGFloat(first.y)))
                for point in stroke.points.dropFirst() {
                    path.addLine(to: CGPoint(x: CGFloat(point.x), y: CGFloat(point.y)))
                }
                let color = stroke.style.color
                cg.setStrokeColor(UIColor(red: CGFloat(color.red), green: CGFloat(color.green), blue: CGFloat(color.blue), alpha: CGFloat(color.alpha)).cgColor)
                cg.setLineWidth(max(1, min(64, CGFloat(stroke.style.thickness) * CGFloat(layout.canvasSize) / 0.05)))
                cg.addPath(path.cgPath)
                cg.strokePath()
                if stroke.points.count == 1 {
                    let diameter = max(2, CGFloat(stroke.style.thickness) * CGFloat(layout.canvasSize) / 0.05)
                    cg.fillEllipse(in: CGRect(x: CGFloat(first.x) - diameter / 2, y: CGFloat(first.y) - diameter / 2, width: diameter, height: diameter))
                }
            }
        }
        guard data.count <= AirCanvasDocumentLimits.maximumFileBytes else {
            throw AirCanvasDocumentError.fileTooLarge
        }
        return data
    }

    @MainActor
    static func writeTemporaryPNG(for project: CanvasProject) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "AirCanvasExports", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let fileURL = directory.appending(path: "\(UUID().uuidString).png")
            try pngData(for: project).write(to: fileURL, options: .atomic)
            return fileURL
        } catch let error as AirCanvasDocumentError {
            throw error
        } catch {
            throw AirCanvasDocumentError.unableToWriteExport
        }
    }
}
