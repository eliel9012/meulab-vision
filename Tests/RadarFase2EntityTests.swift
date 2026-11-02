import Foundation
import RealityKit
import Testing
@testable import MeuLabVision

@Suite("Radar fase 2 — entities and motion")
struct RadarFase2EntityTests {
    private func extrapolate(speed: Double = 500, track: Double = 0, rate: Double = 0,
                             altitude: Double = 3_000, ground: Bool = false,
                             elapsed: Double) -> AircraftMotionComponent.Extrapolated {
        AircraftMotionComponent.extrapolate(latitude: -20.5, longitude: -47.4, altitudeMeters: altitude,
                                            groundSpeedKnots: speed, trackDegrees: track,
                                            baroRateFeetPerMinute: rate, isOnGround: ground,
                                            elapsed: elapsed)
    }

    @Test func zeroElapsedKeepsFix() {
        let state = extrapolate(elapsed: 0)
        #expect(state == .init(latitude: -20.5, longitude: -47.4, altitudeMeters: 3_000))
    }

    @Test func dueNorthMovesLatitudeOnly() {
        let state = extrapolate(track: 0, elapsed: 10)
        let metres = 500 * 1_852.0 / 3_600 * 10
        let expected = -20.5 + metres / 6_371_000 * 180 / .pi
        #expect(abs(state.latitude - expected) < 1e-9)
        #expect(abs(state.longitude - -47.4) < 1e-9)
    }

    @Test func dueEastMovesLongitudeOnly() {
        let state = extrapolate(track: 90, elapsed: 10)
        #expect(abs(state.latitude - -20.5) < 1e-9)
        #expect(state.longitude > -47.4)
    }

    @Test func horizonIsCappedAtThirtySeconds() {
        #expect(extrapolate(rate: 1_000, elapsed: 60) == extrapolate(rate: 1_000, elapsed: 30))
        #expect(extrapolate(elapsed: -5) == extrapolate(elapsed: 0))
    }

    @Test func climbAndGroundLock() {
        let climbing = extrapolate(rate: 600, elapsed: 30)
        #expect(abs(climbing.altitudeMeters - (3_000 + 600 * 0.3048 / 2)) < 1e-6)
        #expect(extrapolate(rate: 600, ground: true, elapsed: 30).altitudeMeters == 3_000)
        #expect(extrapolate(rate: -10_000, altitude: 100, elapsed: 30).altitudeMeters == 0)
    }

    @Test func boxBatchIsValid() {
        var batch = RadarMeshBatch()
        batch.addBox(size: [1, 1, 1])
        #expect(batch.positions.count == 24)
        #expect(batch.triangleCount == 12)
        #expect(batch.normals.count == batch.positions.count)
    }

    @Test func detailedGeometryHasAllSlotsAndValidIndices() {
        for propeller in [true, false] {
            let slots = AircraftGeometry.detailed(propeller: propeller)
            #expect(slots.count == AircraftMaterialSlot.allCases.count)
            for batch in slots {
                #expect(!batch.isEmpty)
                #expect(batch.indices.allSatisfy { Int($0) < batch.positions.count })
            }
            let low = AircraftGeometry.lowDetail(propeller: propeller)
            #expect(low.count == 1)
            #expect(low[0].triangleCount < slots.reduce(0) { $0 + $1.triangleCount })
        }
    }

    @Test func polylineTubeSkipsDegenerateSegments() {
        var batch = RadarMeshBatch()
        batch.addPolylineTube([[0, 0, 0], [0, 0, 0], [1, 0, 0]], width: 0.01, height: 0.01, closed: false)
        #expect(batch.triangleCount == 12)
        var ring = RadarMeshBatch()
        ring.addPolylineTube([[0, 0, 0], [1, 0, 0], [1, 0, 1]], width: 0.01, height: 0.01, closed: true)
        #expect(ring.triangleCount == 36)
    }

    @Test func terrainResolutionDividesFullGrid() {
        #expect(RadarTerrain.validResolution(33) == 33)
        #expect(RadarTerrain.validResolution(40) == 33)
        #expect(RadarTerrain.validResolution(65) == 65)
    }

    @Test func accessibilityTextIsSpoken() {
        let text = AircraftEntityFactory.accessibilityText(for: aircraft(callsign: " GLO1234 "))
        #expect(text.label == "GLO1234")
        #expect(text.value == "altitude 10000 pés, velocidade 450 nós, rumo 270 graus")
        #expect(AircraftEntityFactory.accessibilityText(for: aircraft(callsign: "")).label == "E48ABC")
    }

    @MainActor @Test func hexResolvesFromNestedChild() {
        let factory = AircraftEntityFactory()
        let root = factory.make(aircraft: aircraft(callsign: "GLO1234"))
        let detail = try? #require(root.findEntity(named: AircraftEntityFactory.detailName))
        #expect(detail.flatMap(AircraftEntityFactory.hex(for:)) == "e48abc")
        #expect(AircraftEntityFactory.hex(for: Entity()) == nil)
        #expect(root.components.has(InputTargetComponent.self))
        #expect(root.components.has(AccessibilityComponent.self))
    }

    private func aircraft(callsign: String) -> Aircraft {
        Aircraft(hex: "e48abc", callsign: callsign, registration: nil, aircraftType: "A320", description: nil,
                 latitude: -20.5, longitude: -47.4, altitudeMeters: 3_048, altitudeKind: .barometric,
                 geometricAltitudeMeters: nil, speedKnots: 450, trackDegrees: 270,
                 verticalRateFeetPerMinute: 0, seenSeconds: 1, seenPositionSeconds: 1, rssi: nil,
                 category: nil, squawk: nil, sourceType: nil)
    }
}
