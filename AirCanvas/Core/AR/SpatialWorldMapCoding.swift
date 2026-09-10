import ARKit
import Foundation

enum SpatialWorldMapError: Error, Equatable, Sendable, LocalizedError {
    case unavailable
    case encodingFailed
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "A spatial reference is not available yet. Scan more of the area and try again."
        case .encodingFailed:
            "AirCanvas could not prepare the spatial reference for saving."
        case .decodingFailed:
            "AirCanvas could not read the saved spatial reference."
        }
    }
}

/// Keeps ARKit secure-coding details out of the project domain and repository layers.
enum SpatialWorldMapCoder {
    static func archive(_ worldMap: ARWorldMap) throws -> Data {
        do {
            return try NSKeyedArchiver.archivedData(withRootObject: worldMap, requiringSecureCoding: true)
        } catch {
            throw SpatialWorldMapError.encodingFailed
        }
    }

    static func unarchive(_ data: Data) throws -> ARWorldMap {
        do {
            guard let worldMap = try NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: data) else {
                throw SpatialWorldMapError.decodingFailed
            }
            return worldMap
        } catch let error as SpatialWorldMapError {
            throw error
        } catch {
            throw SpatialWorldMapError.decodingFailed
        }
    }

    static func mappingQuality(from status: ARFrame.WorldMappingStatus) -> SpatialMappingQuality {
        switch status {
        case .notAvailable: .unavailable
        case .limited: .limited
        case .extending: .extending
        case .mapped: .mapped
        @unknown default: .unavailable
        }
    }
}

enum SpatialRelocalizationState: Equatable, Sendable {
    case none
    case preparing
    case scanning
    case localized
    case failed(SpatialRelocalizationFailure)
    case fallback

    var guidance: String? {
        switch self {
        case .preparing, .scanning:
            "Finding your canvas. Move your device slowly around the area where it was created."
        case .localized:
            "Canvas found."
        case .failed(.spatialReferenceUnavailable):
            "The saved spatial reference could not be read. You can open without spatial alignment."
        case .failed(.notFound):
            "Still looking for this canvas. Continue scanning, open without spatial alignment, or return Home."
        case .none, .fallback:
            nil
        }
    }
}

enum SpatialRelocalizationFailure: Equatable, Sendable {
    case spatialReferenceUnavailable
    case notFound
}
