import Foundation
import RealityKit
import simd

/// Triangle soup for one material slot. Pure value type, testable without RealityKit.
struct RadarMeshBatch: Sendable, Equatable {
    var positions: [SIMD3<Float>] = []
    var normals: [SIMD3<Float>] = []
    var indices: [UInt32] = []

    var isEmpty: Bool { indices.isEmpty }
    var triangleCount: Int { indices.count / 3 }

    /// Placement of a primitive: scale, then rotate, then translate.
    struct Placement: Sendable {
        var translation: SIMD3<Float> = .zero
        var rotation = simd_quatf(angle: 0, axis: [0, 1, 0])
        var scale: SIMD3<Float> = .one

        func point(_ p: SIMD3<Float>) -> SIMD3<Float> { rotation.act(p * scale) + translation }
        func normal(_ n: SIMD3<Float>) -> SIMD3<Float> { simd_normalize(rotation.act(n / scale)) }
    }

    mutating func addQuad(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>) {
        let cross = simd_cross(b - a, c - a)
        let length = simd_length(cross)
        let normal = length > 0 ? cross / length : SIMD3<Float>(0, 1, 0)
        let base = UInt32(positions.count)
        positions.append(contentsOf: [a, b, c, d])
        normals.append(contentsOf: [normal, normal, normal, normal])
        indices.append(contentsOf: [base, base + 1, base + 2, base, base + 2, base + 3])
    }

    /// Axis-aligned box centred at the origin, then placed.
    mutating func addBox(size: SIMD3<Float>, _ placement: Placement = .init()) {
        let h = size / 2
        let c: [SIMD3<Float>] = [
            [-h.x, -h.y, -h.z], [h.x, -h.y, -h.z], [h.x, h.y, -h.z], [-h.x, h.y, -h.z],
            [-h.x, -h.y, h.z], [h.x, -h.y, h.z], [h.x, h.y, h.z], [-h.x, h.y, h.z]
        ].map(placement.point)
        addQuad(c[4], c[5], c[6], c[7]) // +Z
        addQuad(c[1], c[0], c[3], c[2]) // -Z
        addQuad(c[5], c[1], c[2], c[6]) // +X
        addQuad(c[0], c[4], c[7], c[3]) // -X
        addQuad(c[7], c[6], c[2], c[3]) // +Y
        addQuad(c[0], c[1], c[5], c[4]) // -Y
    }

    /// Cylinder along +Y centred at the origin (same convention as `generateCylinder`).
    mutating func addCylinder(height: Float, radius: Float, segments: Int = 12, _ placement: Placement = .init()) {
        let half = height / 2
        let base = UInt32(positions.count)
        for i in 0...segments {
            let a = Float(i) / Float(segments) * 2 * .pi
            let n = SIMD3<Float>(cos(a), 0, sin(a))
            positions.append(placement.point([n.x * radius, -half, n.z * radius]))
            positions.append(placement.point([n.x * radius, half, n.z * radius]))
            normals.append(placement.normal(n))
            normals.append(placement.normal(n))
        }
        for i in 0..<UInt32(segments) {
            let a = base + i * 2, b = a + 1, c = a + 2, d = a + 3
            indices.append(contentsOf: [a, b, c, c, b, d])
        }
        addDisc(radius: radius, y: half, up: true, segments: segments, placement)
        addDisc(radius: radius, y: -half, up: false, segments: segments, placement)
    }

    /// Cone along +Y (apex at +height/2), centred at the origin like `generateCone`.
    mutating func addCone(height: Float, radius: Float, segments: Int = 12, _ placement: Placement = .init()) {
        let half = height / 2
        let slope = radius / height
        for i in 0..<segments {
            let a0 = Float(i) / Float(segments) * 2 * .pi
            let a1 = Float(i + 1) / Float(segments) * 2 * .pi
            let am = (a0 + a1) / 2
            let base = UInt32(positions.count)
            positions.append(placement.point([cos(a0) * radius, -half, sin(a0) * radius]))
            positions.append(placement.point([0, half, 0]))
            positions.append(placement.point([cos(a1) * radius, -half, sin(a1) * radius]))
            for angle in [a0, am, a1] {
                normals.append(placement.normal(simd_normalize([cos(angle), slope, sin(angle)])))
            }
            indices.append(contentsOf: [base, base + 1, base + 2])
        }
        addDisc(radius: radius, y: -half, up: false, segments: segments, placement)
    }

    /// UV sphere centred at the origin.
    mutating func addSphere(radius: Float, rings: Int = 6, segments: Int = 10, _ placement: Placement = .init()) {
        let base = UInt32(positions.count)
        for ring in 0...rings {
            let phi = Float(ring) / Float(rings) * .pi
            for segment in 0...segments {
                let theta = Float(segment) / Float(segments) * 2 * .pi
                let n = SIMD3<Float>(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta))
                positions.append(placement.point(n * radius))
                normals.append(placement.normal(n))
            }
        }
        let stride = UInt32(segments + 1)
        for ring in 0..<UInt32(rings) {
            for segment in 0..<UInt32(segments) {
                let a = base + ring * stride + segment
                let b = a + stride
                indices.append(contentsOf: [a, a + 1, b, a + 1, b + 1, b])
            }
        }
    }

    /// Flat quad outline (XZ) extruded by `halfThickness` on Y.
    mutating func addSlab(outline: [SIMD2<Float>], halfThickness: Float) {
        guard outline.count == 4 else { return }
        var ring = outline
        // Keep a consistent winding so top faces point up.
        let area = zip(ring, ring.dropFirst() + [ring[0]]).reduce(Float(0)) { $0 + ($1.0.x * $1.1.y - $1.1.x * $1.0.y) }
        if area < 0 { ring.reverse() }
        let top = ring.map { SIMD3<Float>($0.x, halfThickness, $0.y) }
        let bottom = ring.map { SIMD3<Float>($0.x, -halfThickness, $0.y) }
        addQuad(top[3], top[2], top[1], top[0])
        addQuad(bottom[0], bottom[1], bottom[2], bottom[3])
        for index in 0..<4 {
            let next = (index + 1) % 4
            addQuad(top[next], bottom[next], bottom[index], top[index])
        }
    }

    /// Thin rectangular tube following a polyline: one box per segment, slightly
    /// extended so joints do not show gaps. Used for range rings, edges and trails.
    mutating func addPolylineTube(_ points: [SIMD3<Float>], width: Float, height: Float, closed: Bool) {
        guard points.count >= 2 else { return }
        var path = points
        if closed { path.append(points[0]) }
        for (start, end) in zip(path, path.dropFirst()) {
            let delta = end - start
            let length = simd_length(delta)
            guard length > 1e-5 else { continue }
            let direction = delta / length
            let placement = Placement(
                translation: (start + end) / 2,
                rotation: simd_quatf(from: [0, 0, 1], to: direction)
            )
            addBox(size: [width, height, length + width], placement)
        }
    }

    private mutating func addDisc(radius: Float, y: Float, up: Bool, segments: Int, _ placement: Placement) {
        let center = UInt32(positions.count)
        let n = placement.normal(up ? [0, 1, 0] : [0, -1, 0])
        positions.append(placement.point([0, y, 0]))
        normals.append(n)
        for i in 0...segments {
            let a = Float(i) / Float(segments) * 2 * .pi
            positions.append(placement.point([cos(a) * radius, y, sin(a) * radius]))
            normals.append(n)
        }
        for i in 0..<UInt32(segments) {
            let a = center + 1 + i
            indices.append(contentsOf: up ? [center, a + 1, a] : [center, a, a + 1])
        }
    }
}

extension RadarMeshBatch {
    /// One mesh with one part per non-empty batch; part `i` uses material index `i`.
    /// Empty slots keep their index so a fixed material array always lines up.
    @MainActor
    static func meshResource(_ batches: [RadarMeshBatch], name: String) throws -> MeshResource {
        let descriptors = batches.enumerated().compactMap { index, batch -> MeshDescriptor? in
            guard !batch.isEmpty else { return nil }
            var descriptor = MeshDescriptor(name: "\(name)-\(index)")
            descriptor.positions = .init(batch.positions)
            descriptor.normals = .init(batch.normals)
            descriptor.primitives = .triangles(batch.indices)
            descriptor.materials = .allFaces(UInt32(index))
            return descriptor
        }
        return try MeshResource.generate(from: descriptors)
    }
}
