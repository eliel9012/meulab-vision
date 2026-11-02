import Foundation
import Testing
@testable import MeuLabVision

@Suite("ADS-B decoder")
struct ADSBDecoderTests {
    let snapshot: AircraftSnapshot

    init() throws {
        snapshot = try AircraftDecoder.decode(Fixture.data("readsb_aircraft"))
    }

    private func aircraft(_ hex: String) throws -> Aircraft {
        try #require(snapshot.aircraft.first { $0.hex == hex })
    }

    @Test func snapshotMetadataAndDeduplication() {
        #expect(snapshot.messages == 123_456)
        #expect(snapshot.generatedAt == Date(timeIntervalSince1970: 1_761_832_800.5))
        #expect(snapshot.aircraft.map(\.hex) == ["e48a1b", "e4ffff", "e40001", "e40002"])
    }

    @Test func fullAircraft() throws {
        let a = try aircraft("e48a1b")
        #expect(a.callsign == "GLO1234")
        #expect(a.registration == "PR-GXA")
        #expect(a.aircraftType == "B38M")
        #expect(a.altitudeKind == .barometric)
        #expect(abs((a.altitudeMeters ?? 0) - 10_668) < 0.001)
        #expect(abs((a.geometricAltitudeMeters ?? 0) - 10_820.4) < 0.001)
        #expect(a.trackDegrees == 10)
        #expect(a.speedKnots == 450.5)
        #expect(a.verticalRateFeetPerMinute == -64)
        #expect(a.squawk == "7000")
        #expect(a.hasPosition)
    }

    @Test func groundAndLossyValues() throws {
        let a = try aircraft("e4ffff")
        #expect(a.callsign == "E4FFFF")
        #expect(a.altitudeKind == .ground)
        #expect(a.altitudeMeters == 0)
        #expect(a.speedKnots == nil)
        #expect(a.seenPositionSeconds == nil)
        #expect(a.squawk == "1200")
        #expect(a.latitude == -20.51)
        #expect(a.longitude == -47.40)
    }

    @Test func invalidPositionAndGeometricFallback() throws {
        let a = try aircraft("e40001")
        #expect(!a.hasPosition)
        #expect(a.altitudeKind == .geometric)
        #expect(abs((a.altitudeMeters ?? 0) - 3_657.6) < 0.001)
        #expect(a.verticalRateFeetPerMinute == 512)
        let b = try aircraft("e40002")
        #expect(b.altitudeKind == .unavailable)
        #expect(b.altitudeMeters == nil)
    }

    @Test func recentPositionUsesReceiptAge() throws {
        let a = try aircraft("e48a1b")
        let received = Date(timeIntervalSince1970: 1_000)
        #expect(a.positionAge(at: received, now: received.addingTimeInterval(10)) == 11.2)
        #expect(a.hasRecentPosition(at: received, now: received.addingTimeInterval(20)))
        #expect(!a.hasRecentPosition(at: received, now: received.addingTimeInterval(40)))
    }

    @Test func malformedRootThrowsAndMissingListIsEmpty() throws {
        #expect(throws: (any Error).self) { try AircraftDecoder.decode(Data("[]".utf8)) }
        let empty = try AircraftDecoder.decode(Data(#"{"now":"x"}"#.utf8))
        #expect(empty.aircraft.isEmpty)
        #expect(empty.generatedAt == nil)
    }
}
