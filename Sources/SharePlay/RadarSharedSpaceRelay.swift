import ARKit
import Foundation

/// Nearby shared coordinate space (ARKit `SharedCoordinateSpaceProvider`, visionOS 26+).
///
/// The provider produces opaque alignment data that the app must deliver to the
/// other nearby devices itself; here it rides the SharePlay messenger
/// (`RadarSyncMessage.Payload.coordinateSpace`). ARKit providers only run while
/// the app has an open ImmersiveSpace, so this is started on demand
/// (`RadarSharePlayCoordinator.startSharedCoordinateSpace()`) by the immersive
/// scene, never by the shared-space volume. Volumes/windows in a nearby
/// SharePlay session are already aligned by the system (SystemCoordinator).
@MainActor
final class RadarSharedSpaceRelay {
    private let session = ARKitSession()
    private var provider: SharedCoordinateSpaceProvider?
    private var pumpTask: Task<Void, Never>?
    private var eventTask: Task<Void, Never>?
    private(set) var isSharingEnabled = false
    private(set) var connectedParticipants: [UUID] = []

    /// Called with data ARKit wants sent to `recipients` (ARKit participant ids).
    var outbound: ((Data, [UUID]) -> Void)?

    static var isSupported: Bool { SharedCoordinateSpaceProvider.isSupported }
    var isRunning: Bool { provider != nil }

    func start() async throws {
        guard Self.isSupported, provider == nil else { return }
        let provider = SharedCoordinateSpaceProvider()
        try await session.run([provider])
        self.provider = provider

        eventTask = Task { [weak self] in
            for await event in provider.eventUpdates {
                guard let self else { return }
                switch event {
                case .sharingEnabled: self.isSharingEnabled = true
                case .sharingDisabled: self.isSharingEnabled = false
                case .connectedParticipantIdentifiers(let participants): self.connectedParticipants = participants
                @unknown default: break
                }
            }
        }
        // ARKit exposes outgoing data by polling; ~30 Hz is plenty for alignment.
        pumpTask = Task { [weak self] in
            while !Task.isCancelled {
                if let next = provider.nextCoordinateSpaceData {
                    self?.outbound?(next.data, next.recipientIdentifiers)
                } else {
                    try? await Task.sleep(for: .milliseconds(33))
                }
            }
        }
    }

    /// Incoming data from another participant; ignored if not addressed to us.
    func receive(data: Data, recipients: [UUID]) {
        guard let provider,
              recipients.isEmpty || recipients.contains(provider.participantIdentifier),
              let payload = SharedCoordinateSpaceProvider.CoordinateSpaceData(data: data) else { return }
        provider.push(data: payload)
    }

    func stop() {
        pumpTask?.cancel()
        eventTask?.cancel()
        pumpTask = nil
        eventTask = nil
        provider = nil
        isSharingEnabled = false
        connectedParticipants = []
        session.stop()
    }
}
