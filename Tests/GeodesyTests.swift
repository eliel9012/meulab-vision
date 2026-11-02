import Foundation
import Testing
@testable import MeuLabVision

@Suite("Geodesy")
struct GeodesyTests {
    @Test func ecefOnEquatorAndPole() {
        let equator = Geodesy.ecef(.init(latitudeDegrees: 0, longitudeDegrees: 0, altitudeMeters: 0))
        #expect(abs(equator.x - Geodesy.semiMajorAxis) < 1e-6)
        #expect(abs(equator.y) < 1e-6)
        #expect(abs(equator.z) < 1e-6)
        let pole = Geodesy.ecef(.init(latitudeDegrees: 90, longitudeDegrees: 0, altitudeMeters: 0))
        #expect(abs(pole.z - 6_356_752.314245) < 0.001)
    }

    @Test func enuOfOriginIsZeroAndAxesAreOriented() {
        let origin = Geodesy.approximateFranca
        let zero = Geodesy.enu(origin, relativeTo: origin)
        #expect(abs(zero.east) < 1e-6 && abs(zero.north) < 1e-6 && abs(zero.up) < 1e-6)

        let north = Geodesy.enu(.init(latitudeDegrees: origin.latitudeDegrees + 0.1,
                                      longitudeDegrees: origin.longitudeDegrees, altitudeMeters: 0), relativeTo: origin)
        #expect(north.north > 11_000 && north.north < 11_100)
        #expect(abs(north.east) < 1)

        let east = Geodesy.enu(.init(latitudeDegrees: origin.latitudeDegrees,
                                     longitudeDegrees: origin.longitudeDegrees + 0.1, altitudeMeters: 0), relativeTo: origin)
        #expect(east.east > 10_000 && east.east < 10_600)

        let up = Geodesy.enu(.init(latitudeDegrees: origin.latitudeDegrees,
                                   longitudeDegrees: origin.longitudeDegrees, altitudeMeters: 1_000), relativeTo: origin)
        #expect(abs(up.up - 1_000) < 1e-3)
        #expect(abs(up.horizontalDistanceMeters) < 1e-3)
    }

    @Test func surfaceCoordinateRoundTripsThroughENU() {
        let origin = Geodesy.approximateFranca
        let atOrigin = Geodesy.surfaceCoordinate(eastMeters: 0, northMeters: 0)
        #expect(abs(atOrigin.latitudeDegrees - origin.latitudeDegrees) < 1e-7)
        #expect(abs(atOrigin.longitudeDegrees - origin.longitudeDegrees) < 1e-7)

        let point = Geodesy.surfaceCoordinate(eastMeters: 30_000, northMeters: -20_000)
        let back = Geodesy.enu(point, relativeTo: origin)
        #expect(abs(back.east - 30_000) < 1)
        #expect(abs(back.north + 20_000) < 1)
    }

    @Test func visualPositionScalesAndRejectsInvalid() throws {
        let enu = ENUCoordinate(east: 50_000, north: 100_000, up: 0)
        let p = try #require(Geodesy.visualPosition(enu: enu, displayedAltitudeMeters: 10_000,
                                                    radiusKilometers: 100, verticalExaggeration: 1))
        let scale = Double(RadarVisualGeometry.mapRadius) / 100_000
        #expect(abs(p.x - 50_000 * scale) < 1e-9)
        #expect(abs(p.z + 100_000 * scale) < 1e-9)
        #expect(p.y > Double(RadarVisualGeometry.groundY))
        #expect(Geodesy.visualPosition(enu: enu, displayedAltitudeMeters: 0, radiusKilometers: 0, verticalExaggeration: 1) == nil)
        #expect(Geodesy.visualPosition(enu: enu, displayedAltitudeMeters: .nan, radiusKilometers: 100, verticalExaggeration: 1) == nil)
    }

    @Test func unitConversions() {
        #expect(Geodesy.feetToMeters(1_000) == 304.8)
        #expect(abs(Geodesy.knotsToKilometersPerHour(100) - 185.2) < 1e-9)
    }
}
