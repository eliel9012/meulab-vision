import GroupActivities
import SwiftUI

/// Top ornament of the radar volume: starts SharePlay ("Compartilhar radar") or,
/// while a session is active, shows the participant count and a leave button.
struct RadarSharePlayButton: View {
    @Environment(FlightStore.self) private var store

    var body: some View {
        let sharePlay = store.sharePlay
        HStack(spacing: 12) {
            if sharePlay.isActive {
                Label(participantsText(sharePlay), systemImage: "shareplay")
                    .font(.callout)
                Button("Sair", systemImage: "xmark") { sharePlay.leave() }
                    .labelStyle(.iconOnly)
                    .accessibilityLabel("Sair do SharePlay")
            } else {
                ShareLink(item: RadarGroupActivity(), preview: SharePreview("Radar MeuLab")) {
                    Label("Compartilhar radar", systemImage: "shareplay")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassBackgroundEffect()
    }

    private func participantsText(_ sharePlay: RadarSharePlayCoordinator) -> String {
        let total = sharePlay.participantCount
        let nearby = sharePlay.nearbyParticipantCount
        let base = total == 1 ? "1 pessoa" : "\(total) pessoas"
        return nearby > 0 ? "\(base) · \(nearby) por perto" : base
    }
}

enum RadarSharePlayLayout {
    /// Top edge facing the current viewpoint (mirrors the bottom ornament).
    static func ornamentAnchor(for azimuth: SquareAzimuth) -> UnitPoint3D {
        switch azimuth {
        case .front: .topFront
        case .back: .topBack
        case .left: .topLeading
        case .right: .topTrailing
        }
    }
}
