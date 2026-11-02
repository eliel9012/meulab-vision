import Foundation
import MapKit
import RealityKit
import Testing
@testable import MeuLabVision

struct Fase6WAVTests {
    @Test func headerIsRIFFWave() {
        let samples: [Float] = [0, 0.5, -0.5, 1]
        let data = AlertChimeWAV.data(samples: samples, sampleRate: 44_100)
        #expect(data.count == AlertChimeWAV.headerSize + samples.count * 2)
        #expect(String(decoding: data[0..<4], as: UTF8.self) == "RIFF")
        #expect(String(decoding: data[8..<12], as: UTF8.self) == "WAVE")
        #expect(String(decoding: data[12..<16], as: UTF8.self) == "fmt ")
        #expect(String(decoding: data[36..<40], as: UTF8.self) == "data")
        #expect(readUInt32(data, at: 4) == UInt32(data.count - 8))
        #expect(readUInt32(data, at: 24) == 44_100)
        #expect(readUInt32(data, at: 40) == UInt32(samples.count * 2))
        #expect(readUInt16(data, at: 20) == 1)   // PCM
        #expect(readUInt16(data, at: 22) == 1)   // mono
        #expect(readUInt16(data, at: 34) == 16)  // bits
        #expect(readUInt16(data, at: 44 + 6) == UInt16(Int16.max))  // sample 1.0
    }

    @Test func chimeIsShort() {
        let samples = AlertChimeWAV.chimeSamples()
        let seconds = Double(samples.count) / AlertChimeWAV.sampleRate
        #expect(seconds > 0.3 && seconds < 1)
        #expect(samples.allSatisfy { abs($0) <= 1 })
    }

    private func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        data[offset..<offset + 4].enumerated().reduce(0) { $0 | UInt32($1.element) << (8 * $1.offset) }
    }

    private func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
        UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
    }
}

struct Fase6ChimeGateTests {
    @Test func firstSnapshotPrimesWithoutChime() {
        var gate = AlertChimeGate()
        let r1 = gate.shouldChime(unacknowledgedIDs: ["a", "b"])
        #expect(!r1)
        let r2 = gate.shouldChime(unacknowledgedIDs: ["a"])
        #expect(!r2)
        let r3 = gate.shouldChime(unacknowledgedIDs: ["a", "c"])
        #expect(r3)
        let r4 = gate.shouldChime(unacknowledgedIDs: ["c"])
        #expect(!r4)
    }
}

@MainActor
struct Fase6SpatialAudioTests {
    @Test func pingUsesGentleRolloff() {
        #expect(RadarPingAudio.rolloffFactor > 0 && RadarPingAudio.rolloffFactor < 1)
        #expect(RadarPingAudio.distanceAttenuation == .rolloff(factor: RadarPingAudio.rolloffFactor))
        #expect(RadarPingAudio.component().distanceAttenuation == RadarPingAudio.distanceAttenuation)
    }

    @Test func sessionIsHeadTrackedAutomatic() {
        let experience = SpatialAudioSession.intendedExperience
        #expect(experience.soundStageSize == .automatic)
        #expect(experience.anchoringStrategy == .automatic)
    }

    @Test func chimeAnchorsToSceneWithSmallStage() {
        let anchored = AlertChimePlayer.experience(sceneIdentifier: "scene-1")
        #expect(anchored.anchoringStrategy == .scene(identifier: "scene-1"))
        #expect(anchored.soundStageSize == .small)
        #expect(AlertChimePlayer.experience(sceneIdentifier: nil).anchoringStrategy == .automatic)
    }
}

@MainActor
struct Fase6TerrainTests {
    @Test func imageryUsesRealisticElevation() {
        let imagery = RadarMapSnapshot.configuration(for: .imagery)
        #expect(imagery is MKImageryMapConfiguration)
        #expect(imagery.elevationStyle == .realistic)
    }

    @Test func hybridRealisticWithoutPOIs() throws {
        let hybrid = try #require(RadarMapSnapshot.configuration(for: .hybrid) as? MKHybridMapConfiguration)
        #expect(hybrid.elevationStyle == .realistic)
        #expect(hybrid.pointOfInterestFilter == .excludingAll)
    }

    @Test func standardStaysFlat() {
        #expect(RadarMapSnapshot.configuration(for: .standard).elevationStyle == .flat)
    }
}
