import AVFAudio
import OSLog

/// App-wide audio session setup: head-tracked spatial audio with automatic
/// sound stage and anchoring. Individual players (alert chime) can still pin
/// themselves to a specific scene.
@MainActor
enum SpatialAudioSession {
    private static let log = Logger(subsystem: "MeuLabVision", category: "audio")
    private static var configured = false

    static let intendedExperience: AVAudioSession.HeadTrackedSpatialExperience =
        .headTracked(soundStageSize: .automatic, anchoringStrategy: .automatic)

    /// Idempotent; call once at startup.
    static func configure(session: AVAudioSession = .sharedInstance()) {
        guard !configured else { return }
        configured = true
        do {
            try session.setIntendedSpatialExperience(intendedExperience)
        } catch {
            log.error("setIntendedSpatialExperience failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
