import MapKit
import RealityKit
import UIKit

struct RadarMapSurface: Sendable {
    let texture: TextureResource
    let textureCoordinates: [SIMD2<Float>]
}

/// Apple Maps snapshot centered on the same receiver used by the iPhone app.
@MainActor
enum RadarMapSnapshot {
    private static let imageSize = CGSize(width: 1_024, height: 1_024)

    static func surface(radiusKilometers: Double, style: RadarMapStyle) async throws -> RadarMapSurface {
        let center = Geodesy.approximateFranca
        // Extra margin accommodates Mercator distortion at the square's corners.
        let latitudeDelta = radiusKilometers * 2.3 / 111.32
        let longitudeDelta = latitudeDelta / cos(center.latitudeDegrees * .pi / 180)
        let coordinate = CLLocationCoordinate2D(
            latitude: center.latitudeDegrees,
            longitude: center.longitudeDegrees
        )

        let options = MKMapSnapshotter.Options()
        options.size = imageSize
        options.traitCollection = UITraitCollection(userInterfaceStyle: .light)
        options.region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
        )
        options.preferredConfiguration = configuration(for: style)

        try Task.checkCancellation()
        let snapshot = try await MKMapSnapshotter(options: options).start()
        try Task.checkCancellation()
        let marker = snapshot.point(for: coordinate)
        let image = UIGraphicsImageRenderer(size: imageSize).image { context in
            snapshot.image.draw(in: CGRect(origin: .zero, size: imageSize))
            drawFranca(at: marker, in: context.cgContext)
        }
        guard let cgImage = image.cgImage else { throw RadarMapError.imageUnavailable }
        let texture = try await TextureResource(
            image: cgImage,
            withName: "franca-apple-map-\(Int(radiusKilometers))-\(style.rawValue)",
            options: .init(semantic: .color)
        )
        let size = RadarVisualGeometry.meshResolution
        let radiusMeters = radiusKilometers * 1_000
        var coordinates: [SIMD2<Float>] = []
        coordinates.reserveCapacity(size * size)
        for row in 0..<size {
            let north = radiusMeters * (1 - Double(row) * 2 / Double(size - 1))
            for column in 0..<size {
                let east = radiusMeters * (Double(column) * 2 / Double(size - 1) - 1)
                let location = Geodesy.surfaceCoordinate(eastMeters: east, northMeters: north)
                let point = snapshot.point(for: .init(latitude: location.latitudeDegrees,
                                                      longitude: location.longitudeDegrees))
                let u = Float(min(1, max(0, point.x / imageSize.width)))
                let v = Float(1 - min(1, max(0, point.y / imageSize.height)))
                coordinates.append([u, v])
            }
        }
        return .init(texture: texture, textureCoordinates: coordinates)
    }

    /// Satellite styles use realistic elevation (terrain shading in the texture);
    /// mesh heights still come from the DEM (`RadarTerrain`). POIs are dropped where
    /// the configuration supports it (imagery has none; `showsPointsOfInterest` is
    /// not available on visionOS).
    static func configuration(for style: RadarMapStyle) -> MKMapConfiguration {
        switch style {
        case .standard:
            return MKStandardMapConfiguration(elevationStyle: .flat)
        case .imagery:
            return MKImageryMapConfiguration(elevationStyle: .realistic)
        case .hybrid:
            let configuration = MKHybridMapConfiguration(elevationStyle: .realistic)
            configuration.pointOfInterestFilter = .excludingAll
            return configuration
        }
    }

    private static func drawFranca(at point: CGPoint, in context: CGContext) {
        UIColor.systemCyan.setFill()
        context.fillEllipse(in: CGRect(x: point.x - 9, y: point.y - 9, width: 18, height: 18))
        UIColor.white.setStroke()
        context.setLineWidth(3)
        context.strokeEllipse(in: CGRect(x: point.x - 12, y: point.y - 12, width: 24, height: 24))
        let title = "FRANCA · SP"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 24), .foregroundColor: UIColor.white
        ]
        let size = title.size(withAttributes: attributes)
        let label = CGRect(x: point.x + 20, y: point.y - 20, width: size.width + 22, height: 43)
        UIColor.black.withAlphaComponent(0.82).setFill()
        UIBezierPath(roundedRect: label, cornerRadius: 9).fill()
        title.draw(at: CGPoint(x: label.minX + 11, y: label.minY + 8), withAttributes: attributes)
    }
}

private enum RadarMapError: Error {
    case imageUnavailable
}
