import simd

/// A persistable three-dimensional point in AirCanvas world/canvas coordinates.
struct CanvasPoint3D: Codable, Equatable, Hashable, Sendable {
    let x: Float
    let y: Float
    let z: Float

    init(x: Float, y: Float, z: Float) throws {
        guard x.isFinite, y.isFinite, z.isFinite else {
            throw CanvasPoint3DValidationError.nonFiniteCoordinate
        }

        self.x = x
        self.y = y
        self.z = z
    }

    init(simdValue: SIMD3<Float>) throws {
        try self.init(x: simdValue.x, y: simdValue.y, z: simdValue.z)
    }

    var simdValue: SIMD3<Float> {
        SIMD3(x, y, z)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            x: container.decode(Float.self, forKey: .x),
            y: container.decode(Float.self, forKey: .y),
            z: container.decode(Float.self, forKey: .z)
        )
    }
}

enum CanvasPoint3DValidationError: Error, Equatable, Sendable {
    case nonFiniteCoordinate
}
