import Foundation

struct GeodeticCoordinate: Sendable {
    let latitudeDegrees: Double
    let longitudeDegrees: Double
    let altitudeMeters: Double
}

struct CartesianCoordinate: Sendable {
    let x: Double
    let y: Double
    let z: Double
}

struct ENUCoordinate: Sendable {
    let east: Double
    let north: Double
    let up: Double

    var horizontalDistanceMeters: Double { hypot(east, north) }
}

/// Coordinate in the RealityKit volume. X east, Y up, -Z north.
struct RadarVisualCoordinate: Sendable {
    let x: Double
    let y: Double
    let z: Double
}

/// WGS84 ellipsoid, Earth-centered Cartesian coordinates and East-North-Up coordinates.
enum Geodesy {
    static let semiMajorAxis = 6_378_137.0
    static let inverseFlattening = 298.257223563
    static let eccentricitySquared = 1 - pow(1 - 1 / inverseFlattening, 2)
    // Same ADS-B receiver position used by MeuLab on iPhone.
    static let approximateFranca = GeodeticCoordinate(latitudeDegrees: -20.51, longitudeDegrees: -47.40, altitudeMeters: 0)

    static func ecef(_ c: GeodeticCoordinate) -> CartesianCoordinate {
        let lat = c.latitudeDegrees * .pi / 180
        let lon = c.longitudeDegrees * .pi / 180
        let sinLat = sin(lat)
        let cosLat = cos(lat)
        let radius = semiMajorAxis / sqrt(1 - eccentricitySquared * sinLat * sinLat)
        return CartesianCoordinate(
            x: (radius + c.altitudeMeters) * cosLat * cos(lon),
            y: (radius + c.altitudeMeters) * cosLat * sin(lon),
            z: (radius * (1 - eccentricitySquared) + c.altitudeMeters) * sinLat
        )
    }

    static func enu(_ c: GeodeticCoordinate, relativeTo origin: GeodeticCoordinate) -> ENUCoordinate {
        let a = ecef(c)
        let b = ecef(origin)
        let dx = a.x - b.x, dy = a.y - b.y, dz = a.z - b.z
        let lat = origin.latitudeDegrees * .pi / 180
        let lon = origin.longitudeDegrees * .pi / 180
        let sinLat = sin(lat), cosLat = cos(lat), sinLon = sin(lon), cosLon = cos(lon)
        return ENUCoordinate(
            east: -sinLon * dx + cosLon * dy,
            north: -sinLat * cosLon * dx - sinLat * sinLon * dy + cosLat * dz,
            up: cosLat * cosLon * dx + cosLat * sinLon * dy + sinLat * dz
        )
    }

    /// WGS84 surface coordinate at an ENU offset from the receiver.
    static func surfaceCoordinate(eastMeters: Double, northMeters: Double) -> GeodeticCoordinate {
        let origin = approximateFranca
        let base = ecef(origin)
        let lat = origin.latitudeDegrees * .pi / 180
        let lon = origin.longitudeDegrees * .pi / 180
        let east = SIMD3(-sin(lon), cos(lon), 0.0)
        let north = SIMD3(-sin(lat) * cos(lon), -sin(lat) * sin(lon), cos(lat))
        let up = SIMD3(cos(lat) * cos(lon), cos(lat) * sin(lon), sin(lat))
        let q = SIMD3(base.x, base.y, base.z) + east * eastMeters + north * northMeters
        let a2 = semiMajorAxis * semiMajorAxis
        let b = semiMajorAxis * (1 - 1 / inverseFlattening)
        let b2 = b * b
        let aa = (up.x * up.x + up.y * up.y) / a2 + up.z * up.z / b2
        let bb = 2 * ((q.x * up.x + q.y * up.y) / a2 + q.z * up.z / b2)
        let cc = (q.x * q.x + q.y * q.y) / a2 + q.z * q.z / b2 - 1
        let height = (-bb + sqrt(max(0, bb * bb - 4 * aa * cc))) / (2 * aa)
        let point = q + up * height
        let longitude = atan2(point.y, point.x)
        let horizontal = hypot(point.x, point.y)
        var latitude = atan2(point.z, horizontal * (1 - eccentricitySquared))
        for _ in 0..<5 {
            let radius = semiMajorAxis / sqrt(1 - eccentricitySquared * pow(sin(latitude), 2))
            latitude = atan2(point.z + eccentricitySquared * radius * sin(latitude), horizontal)
        }
        return .init(latitudeDegrees: latitude * 180 / .pi,
                     longitudeDegrees: longitude * 180 / .pi, altitudeMeters: 0)
    }

    /// Deliberately non-uniform vertical exaggeration for a human-scale volume.
    /// Aircraft height is scaled from receiver elevation; "Y" is not to horizontal scale.
    static func visualPosition(enu: ENUCoordinate, displayedAltitudeMeters: Double,
                               radiusKilometers: Double, verticalExaggeration: Double) -> RadarVisualCoordinate? {
        guard radiusKilometers.isFinite, radiusKilometers > 0,
              verticalExaggeration.isFinite, verticalExaggeration > 0,
              displayedAltitudeMeters.isFinite else { return nil }
        let normalized = Double(RadarVisualGeometry.mapRadius) / (radiusKilometers * 1000)
        let terrain = RadarTerrain.shared
        let baseline = Double(RadarVisualGeometry.groundY)
            + (terrain == nil ? 0 : Double(RadarVisualGeometry.terrainBaseHeight))
        let relativeAltitude = max(0, displayedAltitudeMeters - (terrain?.centerElevationMeters ?? 0))
        return RadarVisualCoordinate(
            x: enu.east * normalized,
            y: baseline + min(0.44, relativeAltitude / 16_000 * 0.24 * verticalExaggeration),
            z: -enu.north * normalized
        )
    }

    static func feetToMeters(_ feet: Double) -> Double { feet * 0.3048 }
    static func knotsToKilometersPerHour(_ knots: Double) -> Double { knots * 1.852 }
}
