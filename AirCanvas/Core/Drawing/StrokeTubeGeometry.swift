import simd

struct StrokeTubeGeometryConfiguration: Equatable, Sendable {
    static let standard = StrokeTubeGeometryConfiguration(radialSegmentCount: 8)

    let radialSegmentCount: Int

    init(radialSegmentCount: Int) {
        self.radialSegmentCount = radialSegmentCount
    }

    func isValid() -> Bool {
        radialSegmentCount >= 3
    }
}

/// Framework-independent triangle data that RealityKit later converts into a mesh resource.
struct StrokeTubeGeometry: Equatable, Sendable {
    let positions: [SIMD3<Float>]
    let normals: [SIMD3<Float>]
    let indices: [UInt32]

    var triangleCount: Int {
        indices.count / 3
    }
}

struct StrokeTubeGeometryBuilder: Sendable {
    let configuration: StrokeTubeGeometryConfiguration

    init(configuration: StrokeTubeGeometryConfiguration = .standard) {
        precondition(configuration.isValid(), "StrokeTubeGeometryConfiguration must be valid.")
        self.configuration = configuration
    }

    func geometry(for stroke: RenderableStroke) -> StrokeTubeGeometry? {
        guard stroke.style.thickness.isFinite, stroke.style.thickness > 0 else {
            return nil
        }

        let points = nonDegeneratePoints(from: stroke.points.map(\.simdValue))
        guard points.count >= 2 else {
            return nil
        }

        let sideCount = configuration.radialSegmentCount
        let radius = stroke.style.thickness / 2
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var tangents: [SIMD3<Float>] = []
        positions.reserveCapacity((points.count * sideCount) + 2)
        normals.reserveCapacity((points.count * sideCount) + 2)
        tangents.reserveCapacity(points.count)

        for index in points.indices {
            let tangent = tangent(at: index, in: points)
            tangents.append(tangent)
            let reference = abs(simd_dot(tangent, SIMD3<Float>(0, 1, 0))) > 0.9
                ? SIMD3<Float>(1, 0, 0)
                : SIMD3<Float>(0, 1, 0)
            let normalA = simd_normalize(simd_cross(tangent, reference))
            let normalB = simd_normalize(simd_cross(tangent, normalA))

            for side in 0 ..< sideCount {
                let angle = (2 * Float.pi * Float(side)) / Float(sideCount)
                let normal = (cos(angle) * normalA) + (sin(angle) * normalB)
                positions.append(points[index] + (normal * radius))
                normals.append(normal)
            }
        }

        let startCapIndex = UInt32(positions.count)
        positions.append(points[0])
        normals.append(-tangents[0])
        let endCapIndex = UInt32(positions.count)
        positions.append(points[points.count - 1])
        normals.append(tangents[tangents.count - 1])

        var indices: [UInt32] = []
        indices.reserveCapacity(((points.count - 1) * sideCount * 6) + (sideCount * 6))

        for ring in 0 ..< (points.count - 1) {
            let currentOffset = ring * sideCount
            let nextOffset = (ring + 1) * sideCount
            for side in 0 ..< sideCount {
                let nextSide = (side + 1) % sideCount
                let current = UInt32(currentOffset + side)
                let currentNext = UInt32(currentOffset + nextSide)
                let next = UInt32(nextOffset + side)
                let nextNext = UInt32(nextOffset + nextSide)
                indices.append(contentsOf: [current, next, currentNext, currentNext, next, nextNext])
            }
        }

        for side in 0 ..< sideCount {
            let nextSide = (side + 1) % sideCount
            indices.append(contentsOf: [startCapIndex, UInt32(nextSide), UInt32(side)])

            let endOffset = (points.count - 1) * sideCount
            indices.append(contentsOf: [endCapIndex, UInt32(endOffset + side), UInt32(endOffset + nextSide)])
        }

        return StrokeTubeGeometry(positions: positions, normals: normals, indices: indices)
    }

    private func nonDegeneratePoints(from points: [SIMD3<Float>]) -> [SIMD3<Float>] {
        guard let first = points.first else {
            return []
        }

        var result = [first]
        for point in points.dropFirst() where simd_length_squared(point - result[result.count - 1]) > 0.000_000_000_001 {
            result.append(point)
        }
        return result
    }

    private func tangent(at index: Int, in points: [SIMD3<Float>]) -> SIMD3<Float> {
        let direction: SIMD3<Float>
        if index == points.startIndex {
            direction = points[1] - points[0]
        } else if index == points.index(before: points.endIndex) {
            direction = points[index] - points[index - 1]
        } else {
            direction = points[index + 1] - points[index - 1]
        }
        return simd_normalize(direction)
    }
}
