import Foundation
import RealityKit
import UIKit

struct RadarCloudSurface: Sendable {
    let texture: TextureResource
    let textureCoordinates: [SIMD2<Float>]
    let capturedAt: Date
}

enum RadarCloudError: LocalizedError {
    case noTimestamp
    case stale
    case invalidImage

    var errorDescription: String? {
        switch self {
        case .noTimestamp: "Horário da imagem GOES indisponível"
        case .stale: "Imagem GOES desatualizada"
        case .invalidImage: "Imagem GOES inválida"
        }
    }
}

/// NASA GIBS GOES-East infrared imagery. The image is an observation of cloud-top
/// temperature, not a cloud mask or a forecast. WMS 1.3 EPSG:4326 uses lat/lon BBOX order.
@MainActor
enum RadarCloudSnapshot {
    private static let endpoint = "https://gibs.earthdata.nasa.gov/wms/epsg4326/best/wms.cgi"
    private static let layer = "GOES-East_ABI_Band13_Clean_Infrared"
    private static let imageSize = 512

    static func surface(radiusKilometers: Double) async throws -> RadarCloudSurface {
        let timestamp = try await latestTime()
        guard Date().timeIntervalSince(timestamp) < 3 * 60 * 60 else { throw RadarCloudError.stale }
        let bounds = boundsForRadar(radiusKilometers: radiusKilometers)
        var components = URLComponents(string: endpoint)!
        components.queryItems = [
            .init(name: "SERVICE", value: "WMS"),
            .init(name: "REQUEST", value: "GetMap"),
            .init(name: "VERSION", value: "1.3.0"),
            .init(name: "LAYERS", value: layer),
            .init(name: "STYLES", value: ""),
            .init(name: "FORMAT", value: "image/png"),
            .init(name: "TRANSPARENT", value: "TRUE"),
            .init(name: "CRS", value: "EPSG:4326"),
            .init(name: "BBOX", value: "\(bounds.south),\(bounds.west),\(bounds.north),\(bounds.east)"),
            .init(name: "WIDTH", value: "\(imageSize)"),
            .init(name: "HEIGHT", value: "\(imageSize)"),
            .init(name: "TIME", value: ISO8601DateFormatter().string(from: timestamp))
        ]
        let (data, response) = try await URLSession.shared.data(from: components.url!)
        try Task.checkCancellation()
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let image = UIImage(data: data)?.cgImage else { throw RadarCloudError.invalidImage }

        // Infrared colors remain NASA's own. Partial alpha preserves roads and relief below.
        let renderer = UIGraphicsImageRenderer(size: .init(width: imageSize, height: imageSize))
        let translucent = renderer.image { context in
            UIImage(cgImage: image).draw(in: .init(x: 0, y: 0, width: imageSize, height: imageSize),
                                         blendMode: .normal, alpha: 0.48)
        }
        guard let cgImage = translucent.cgImage else { throw RadarCloudError.invalidImage }
        let texture = try await TextureResource(image: cgImage,
                                                withName: "goes-east-\(Int(timestamp.timeIntervalSince1970))",
                                                options: .init(semantic: .color))
        let size = RadarVisualGeometry.meshResolution
        let radiusMeters = radiusKilometers * 1_000
        var coordinates: [SIMD2<Float>] = []
        coordinates.reserveCapacity(size * size)
        for row in 0..<size {
            let north = radiusMeters * (1 - Double(row) * 2 / Double(size - 1))
            for column in 0..<size {
                let east = radiusMeters * (Double(column) * 2 / Double(size - 1) - 1)
                let location = Geodesy.surfaceCoordinate(eastMeters: east, northMeters: north)
                let u = Float((location.longitudeDegrees - bounds.west) / (bounds.east - bounds.west))
                let v = Float((location.latitudeDegrees - bounds.south) / (bounds.north - bounds.south))
                coordinates.append([u, v])
            }
        }
        return .init(texture: texture, textureCoordinates: coordinates, capturedAt: timestamp)
    }

    private static func latestTime() async throws -> Date {
        let url = URL(string: endpoint + "?SERVICE=WMS&REQUEST=GetCapabilities&VERSION=1.3.0")!
        let (data, response) = try await URLSession.shared.data(from: url)
        try Task.checkCancellation()
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw RadarCloudError.noTimestamp }
        // GetCapabilities is several MB of XML: parse off the main actor.
        guard let date = await parseLatestTime(data, layerName: layer) else { throw RadarCloudError.noTimestamp }
        return date
    }

    /// Parses the GIBS capabilities document on the global executor; only the
    /// resulting `Date` hops back to the caller's (main) actor.
    @concurrent
    nonisolated static func parseLatestTime(_ data: Data, layerName: String) async -> Date? {
        let parser = XMLParser(data: data)
        let delegate = GIBSTimeParser(layerName: layerName)
        parser.delegate = delegate
        guard parser.parse(), let time = delegate.latestTime else { return nil }
        return ISO8601DateFormatter().date(from: time)
    }

    private static func boundsForRadar(radiusKilometers: Double) -> (south: Double, west: Double, north: Double, east: Double) {
        let distance = radiusKilometers * 1_100
        let corners = [(-distance, -distance), (-distance, distance), (distance, -distance), (distance, distance)]
            .map { Geodesy.surfaceCoordinate(eastMeters: $0.0, northMeters: $0.1) }
        return (corners.map(\.latitudeDegrees).min()!, corners.map(\.longitudeDegrees).min()!,
                corners.map(\.latitudeDegrees).max()!, corners.map(\.longitudeDegrees).max()!)
    }
}

private final class GIBSTimeParser: NSObject, XMLParserDelegate {
    let layerName: String
    var latestTime: String?
    private var layerMatches: [Bool] = []
    private var readingName = false
    private var name = ""

    init(layerName: String) { self.layerName = layerName }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        switch elementName {
        case "Layer": layerMatches.append(false)
        case "Name": readingName = true; name = ""
        case "Dimension" where layerMatches.last == true && attributeDict["name"] == "time":
            latestTime = attributeDict["default"]
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if readingName { name += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "Name":
            readingName = false
            if name == layerName, !layerMatches.isEmpty { layerMatches[layerMatches.count - 1] = true }
        case "Layer":
            if !layerMatches.isEmpty { layerMatches.removeLast() }
        default: break
        }
    }
}
