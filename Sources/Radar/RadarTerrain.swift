import Foundation
import RealityKit
import simd

enum RadarVisualGeometry {
    static let tableWidth: Float = 1.20
    static let mapRadius: Float = 0.56
    static let groundY: Float = -0.23
    static let terrainBaseHeight: Float = 0.055
    // Vertical relief is enlarged so 1–2 km mountains are visible on a meter-wide model.
    static let terrainExaggeration: Float = 8
    static let meshResolution = 65
}

/// Local WGS84 elevations, derived from public Mapzen Terrarium tiles at 1 km spacing.
struct RadarTerrain {
    private struct Metadata: Decodable {
        let radiusMeters: Int
        let spacingMeters: Int
        let width: Int
        let centerElevationMeters: Int
    }

    static let shared: Self? = load()

    let centerElevationMeters: Double
    private let radiusMeters: Double
    private let spacingMeters: Double
    private let width: Int
    private let heights: [Int16]

    private static func load() -> Self? {
        guard let metadataURL = Bundle.main.url(forResource: "FrancaTerrain", withExtension: "json"),
              let dataURL = Bundle.main.url(forResource: "FrancaTerrain", withExtension: "bin"),
              let metadata = try? JSONDecoder().decode(Metadata.self, from: Data(contentsOf: metadataURL)),
              let data = try? Data(contentsOf: dataURL),
              metadata.width > 1, metadata.spacingMeters > 0,
              metadata.radiusMeters == (metadata.width - 1) * metadata.spacingMeters / 2,
              data.count == metadata.width * metadata.width * 2 else { return nil }
        let bytes = [UInt8](data)
        let values = stride(from: 0, to: bytes.count, by: 2).map { offset in
            Int16(bitPattern: UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8)
        }
        return .init(centerElevationMeters: Double(metadata.centerElevationMeters),
                     radiusMeters: Double(metadata.radiusMeters),
                     spacingMeters: Double(metadata.spacingMeters),
                     width: metadata.width, heights: values)
    }

    /// Outside the grid there is no elevation data: the surface stays flat at the receiver's
    /// level instead of stretching the edge samples outwards.
    func elevation(eastMeters: Double, northMeters: Double) -> Double {
        guard abs(eastMeters) <= radiusMeters, abs(northMeters) <= radiusMeters else {
            return centerElevationMeters
        }
        let column = min(Double(width - 1), max(0, (eastMeters + radiusMeters) / spacingMeters))
        let row = min(Double(width - 1), max(0, (radiusMeters - northMeters) / spacingMeters))
        let x = Int(column), y = Int(row)
        let x2 = min(width - 1, x + 1), y2 = min(width - 1, y + 1)
        let fx = column - Double(x), fy = row - Double(y)
        let northwest = Double(heights[y * width + x])
        let northeast = Double(heights[y * width + x2])
        let southwest = Double(heights[y2 * width + x])
        let southeast = Double(heights[y2 * width + x2])
        return (northwest * (1 - fx) + northeast * fx) * (1 - fy)
             + (southwest * (1 - fx) + southeast * fx) * fy
    }

    func surfaceY(eastMeters: Double, northMeters: Double, radiusKilometers: Double) -> Float {
        let metersPerVisualMeter = radiusKilometers * 1_000 / Double(RadarVisualGeometry.mapRadius)
        let relief = elevation(eastMeters: eastMeters, northMeters: northMeters) - centerElevationMeters
        let scale = Double(RadarVisualGeometry.terrainExaggeration) / metersPerVisualMeter
        return RadarVisualGeometry.groundY + RadarVisualGeometry.terrainBaseHeight + Float(relief * scale)
    }

    func surfaceY(x: Float, z: Float, radiusKilometers: Double) -> Float {
        let metersPerVisualMeter = radiusKilometers * 1_000 / Double(RadarVisualGeometry.mapRadius)
        return surfaceY(eastMeters: Double(x) * metersPerVisualMeter,
                        northMeters: -Double(z) * metersPerVisualMeter,
                        radiusKilometers: radiusKilometers)
    }

    @MainActor
    /// Grid mesh of the terrain. `resolution` may be lower than `meshResolution` for LOD;
    /// texture coordinates (always sampled on the full grid) are then strided.
    func mesh(radiusKilometers: Double, textureCoordinates: [SIMD2<Float>]?, verticalOffset: Float = 0,
              resolution: Int = RadarVisualGeometry.meshResolution) throws -> MeshResource {
        let full = RadarVisualGeometry.meshResolution
        let size = Self.validResolution(resolution)
        let stride = (full - 1) / (size - 1)
        let fullCoordinates = textureCoordinates?.count == full * full ? textureCoordinates : nil
        let visualRadius = RadarVisualGeometry.mapRadius
        let step = visualRadius * 2 / Float(size - 1)
        let metersPerVisualMeter = radiusKilometers * 1_000 / Double(visualRadius)
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var coordinates: [SIMD2<Float>] = []
        var indices: [UInt32] = []
        positions.reserveCapacity(size * size)
        coordinates.reserveCapacity(size * size)
        for row in 0..<size {
            let z = -visualRadius + Float(row) * step
            for column in 0..<size {
                let x = -visualRadius + Float(column) * step
                let y = surfaceY(eastMeters: Double(x) * metersPerVisualMeter,
                                 northMeters: -Double(z) * metersPerVisualMeter,
                                 radiusKilometers: radiusKilometers)
                positions.append([x, y + verticalOffset, z])
                coordinates.append(fullCoordinates?[row * stride * full + column * stride]
                    ?? [Float(column) / Float(size - 1), 1 - Float(row) / Float(size - 1)])
            }
        }
        for row in 0..<size {
            for column in 0..<size {
                let left = positions[row * size + max(0, column - 1)]
                let right = positions[row * size + min(size - 1, column + 1)]
                let top = positions[max(0, row - 1) * size + column]
                let bottom = positions[min(size - 1, row + 1) * size + column]
                normals.append(simd_normalize(simd_cross(bottom - top, right - left)))
            }
        }
        for row in 0..<(size - 1) {
            for column in 0..<(size - 1) {
                let a = UInt32(row * size + column)
                let b = a + 1
                let c = a + UInt32(size)
                let d = c + 1
                indices.append(contentsOf: [a, c, b, b, c, d])
            }
        }
        var descriptor = MeshDescriptor(name: "Franca terrain \(size)")
        descriptor.positions = .init(positions)
        descriptor.normals = .init(normals)
        descriptor.textureCoordinates = .init(coordinates)
        descriptor.primitives = .triangles(indices)
        return try MeshResource.generate(from: [descriptor])
    }

    /// Largest resolution <= `requested` whose grid lines coincide with the full grid.
    static func validResolution(_ requested: Int) -> Int {
        let full = RadarVisualGeometry.meshResolution
        var size = min(full, max(2, requested))
        while (full - 1) % (size - 1) != 0 { size -= 1 }
        return size
    }
}
