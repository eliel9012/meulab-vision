import AVFAudio
import Foundation
import RealityKit

/// Plays the procedural radar ping as spatial audio on an aircraft marker.
/// One shared throttle for every scene (volume + immersive) → max 1 ping / 2 s overall.
@MainActor
final class RadarPingPlayer {
    static let shared = RadarPingPlayer()

    private var throttle = RadarPingThrottle(interval: 2)
    private var resources: [String: AudioBufferResource] = [:]
    private static let emitterName = "radar.pingEmitter"

    /// Returns true when the ping was actually played.
    @discardableResult
    func play(_ event: RadarPingEvent, on entity: Entity,
              now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        guard entity.scene != nil, let resource = resource(for: event),
              throttle.allow(at: now) else { return false }
        let emitter = emitter(on: entity)
        emitter.playAudio(resource)
        return true
    }

    /// Child emitter so the marker's own components stay untouched.
    private func emitter(on entity: Entity) -> Entity {
        if let existing = entity.findEntity(named: Self.emitterName) { return existing }
        let emitter = Entity()
        emitter.name = Self.emitterName
        emitter.components.set(RadarPingAudio.component())
        entity.addChild(emitter)
        return emitter
    }

    private func resource(for event: RadarPingEvent) -> AudioBufferResource? {
        let key: String
        switch event {
        case .appeared: key = "appeared"
        case .selected: key = "selected"
        }
        if let cached = resources[key] { return cached }
        let samples = RadarPingWaveform.samples(RadarPingWaveform.tone(for: event))
        guard let buffer = RadarPingAudio.buffer(samples: samples),
              let resource = try? AudioBufferResource(buffer: buffer) else { return nil }
        resources[key] = resource
        return resource
    }
}

/// Spatial audio tuning for the aircraft ping emitter.
enum RadarPingAudio {
    static let gain: Audio.Decibel = -8
    /// Gentler than the default inverse-distance rolloff (factor 1): markers sit
    /// 0.5–3 m away (table up to 2.4 m, room scale bigger), so a far ping should
    /// stay audible while still giving a clear near/far cue.
    static let rolloffFactor: Double = 0.6
    static var distanceAttenuation: Audio.DistanceAttenuation { .rolloff(factor: rolloffFactor) }

    /// Mono PCM buffer holding `samples`; nil when there is nothing to play.
    static func buffer(samples: [Float]) -> AVAudioPCMBuffer? {
        guard !samples.isEmpty,
              let format = AVAudioFormat(standardFormatWithSampleRate: RadarPingWaveform.sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        channel.update(from: samples, count: samples.count)
        return buffer
    }

    /// Approximate living room used for the simulated reverb (immersive space only).
    static let reverbRoomSize: SIMD3<Float> = [5, 2.7, 5]

    /// visionOS 27 simulated reverb from a shoebox room mesh.
    static func roomReverb() -> ReverbComponent {
        ReverbComponent(reverb: .simulated(mesh: .shoebox(size: reverbRoomSize)))
    }

    static func component() -> SpatialAudioComponent {
        SpatialAudioComponent(gain: gain, directivity: .beam(focus: 0),
                              distanceAttenuation: distanceAttenuation)
    }
}

/// Applies `EnvironmentBlendingComponent` so real surroundings occlude the radar
/// (immersive space only).
@MainActor
enum RadarOcclusion {
    static func apply(_ enabled: Bool, to entity: Entity) {
        if enabled {
            if !entity.components.has(EnvironmentBlendingComponent.self), entity.components.has(ModelComponent.self) {
                entity.components.set(EnvironmentBlendingComponent(preferredBlendingMode: .occluded(by: .surroundings)))
            }
        } else if entity.components.has(EnvironmentBlendingComponent.self) {
            entity.components.remove(EnvironmentBlendingComponent.self)
        }
        for child in entity.children { apply(enabled, to: child) }
    }
}
