import SwiftUI

/// Opens / closes the immersive radar space. Used by the volume ornament.
struct ImmersiveRadarToggleButton: View {
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @State private var state = ImmersiveRadarState.shared

    var body: some View {
        Button {
            Task { await toggle() }
        } label: {
            Label(state.isOpen ? "Sair do imersivo" : "Imersivo",
                  systemImage: state.isOpen ? "xmark.circle" : "visionpro")
        }
        .disabled(state.isTransitioning)
    }

    private func toggle() async {
        state.isTransitioning = true
        defer { state.isTransitioning = false }
        if state.isOpen {
            await dismissImmersiveSpace()
            return
        }
        switch await openImmersiveSpace(id: ImmersiveRadarState.spaceID) {
        case .opened: state.isOpen = true
        case .userCancelled, .error: state.isOpen = false
        @unknown default: state.isOpen = false
        }
    }
}
