import AudioToolbox
import AVFAudio
import Foundation
import OSLog
import SwiftUI
import UIKit

/// Short two-note chime for new homelab alerts, rendered in memory (no asset)
/// and played head-tracked, anchored to the window that shows the alerts.
@MainActor
final class AlertChimePlayer {
    static let shared = AlertChimePlayer()
    /// UserDefaults / @AppStorage key for the on/off setting.
    static let enabledKey = "alerts.chimeEnabled"

    private static let log = Logger(subsystem: "MeuLabVision", category: "audio")
    private var player: AVAudioPlayer?
    private var sceneIdentifier: String?

    /// Anchors the chime to this scene (UISceneSession.persistentIdentifier).
    func anchor(toScene identifier: String?) {
        guard identifier != sceneIdentifier else { return }
        sceneIdentifier = identifier
        player?.intendedSpatialExperience = Self.experience(sceneIdentifier: identifier)
    }

    static func experience(sceneIdentifier: String?) -> HeadTrackedSpatialAudio {
        if let sceneIdentifier {
            return .headTracked(.scene(identifier: sceneIdentifier), soundStageSize: .small)
        }
        return .headTracked(.automatic, soundStageSize: .small)
    }

    func play() {
        guard UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true else { return }
        do {
            let player = try self.player ?? makePlayer()
            self.player = player
            player.currentTime = 0
            player.play()
        } catch {
            Self.log.error("alert chime failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func makePlayer() throws -> AVAudioPlayer {
        let data = AlertChimeWAV.data(samples: AlertChimeWAV.chimeSamples(),
                                      sampleRate: Int(AlertChimeWAV.sampleRate))
        let player = try AVAudioPlayer(data: data, fileTypeHint: "com.microsoft.waveform-audio")
        player.volume = 0.7
        player.intendedSpatialExperience = Self.experience(sceneIdentifier: sceneIdentifier)
        player.prepareToPlay()
        return player
    }
}

/// Pure WAV (RIFF, 16-bit PCM mono) encoder + chime waveform. Testable without audio hardware.
enum AlertChimeWAV {
    static let sampleRate: Double = 44_100
    static let headerSize = 44

    /// Rising two-note chime (E5 → A5), ~0.5 s.
    static func chimeSamples(sampleRate: Double = sampleRate) -> [Float] {
        let first = RadarPingWaveform.Tone(startFrequency: 659, endFrequency: 659, duration: 0.18, amplitude: 0.55)
        let second = RadarPingWaveform.Tone(startFrequency: 880, endFrequency: 880, duration: 0.32, amplitude: 0.55)
        return RadarPingWaveform.samples(first, sampleRate: sampleRate)
            + RadarPingWaveform.samples(second, sampleRate: sampleRate)
    }

    static func data(samples: [Float], sampleRate: Int) -> Data {
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let blockAlign = channels * bitsPerSample / 8
        let byteRate = UInt32(sampleRate) * UInt32(blockAlign)
        let dataSize = UInt32(samples.count) * UInt32(blockAlign)

        var data = Data(capacity: headerSize + Int(dataSize))
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36) + dataSize, to: &data)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        append(UInt32(16), to: &data)          // PCM fmt chunk size
        append(UInt16(1), to: &data)           // PCM format
        append(channels, to: &data)
        append(UInt32(sampleRate), to: &data)
        append(byteRate, to: &data)
        append(blockAlign, to: &data)
        append(bitsPerSample, to: &data)
        data.append(contentsOf: Array("data".utf8))
        append(dataSize, to: &data)
        for sample in samples {
            let clamped = max(-1, min(1, sample))
            append(Int16(clamped * Float(Int16.max)), to: &data)
        }
        return data
    }

    private static func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }
}

/// Decides when a refresh brought alerts the user has not heard yet.
/// The first snapshot only primes the known set (no chime on launch).
struct AlertChimeGate: Sendable {
    private var known: Set<String>?

    mutating func shouldChime(unacknowledgedIDs: Set<String>) -> Bool {
        defer { known = (known ?? []).union(unacknowledgedIDs) }
        guard let known else { return false }
        return !unacknowledgedIDs.isSubset(of: known)
    }
}

/// Reports the hosting window scene's `persistentIdentifier` (SwiftUI on visionOS
/// does not expose the scene session publicly).
struct SceneIdentifierReader: UIViewRepresentable {
    let onChange: (String?) -> Void

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.onChange = onChange
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {
        uiView.onChange = onChange
    }

    final class ProbeView: UIView {
        var onChange: ((String?) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            onChange?(window?.windowScene?.session.persistentIdentifier)
        }
    }
}
