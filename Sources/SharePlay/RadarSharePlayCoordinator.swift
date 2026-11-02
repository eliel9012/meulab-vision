import Foundation
@preconcurrency import GroupActivities
import Observation

/// Owns the "Radar MeuLab" GroupSession: joins it, configures the spatial
/// template, and syncs `selectedHex` + table transform through `RadarSyncEngine`.
@MainActor
@Observable
final class RadarSharePlayCoordinator {
    private(set) var isActive = false
    private(set) var participantCount = 0
    private(set) var nearbyParticipantCount = 0
    /// Latest table transform received from another participant; the volume applies
    /// it when `remoteTransformRevision` changes.
    private(set) var remoteTransform: RadarTableTransform?
    private(set) var remoteTransformRevision = 0

    /// Receives remote selections (FlightStore applies them to `selectedHex`).
    @ObservationIgnored var applySelection: ((String?) -> Void)?
    /// Current local selection, offered to the group when someone asks for state.
    @ObservationIgnored var currentSelection: (() -> String?)?

    @ObservationIgnored private var engine = RadarSyncEngine()
    @ObservationIgnored private var session: GroupSession<RadarGroupActivity>?
    @ObservationIgnored private var reliable: GroupSessionMessenger?
    @ObservationIgnored private var unreliable: GroupSessionMessenger?
    @ObservationIgnored private var sessionTasks: [Task<Void, Never>] = []
    @ObservationIgnored private var observeTask: Task<Void, Never>?
    @ObservationIgnored private var flushTask: Task<Void, Never>?
    @ObservationIgnored private var sharedSpace: RadarSharedSpaceRelay?

    static let transformFlushDelay: Duration = .milliseconds(250)

    /// Starts listening for SharePlay sessions (idempotent).
    func startObservingSessions() {
        guard observeTask == nil else { return }
        observeTask = Task { [weak self] in
            for await session in RadarGroupActivity.sessions() {
                guard let self else { return }
                await self.configure(session)
            }
        }
    }

    func leave() {
        session?.leave()
        tearDown()
    }

    // MARK: - Local changes → network

    func localSelectionChanged(_ hex: String?) {
        guard session != nil,
              let message = engine.localSelection(hex, now: Self.now) else { return }
        send(message, via: reliable)
    }

    func localTableTransformChanged(_ transform: RadarTableTransform) {
        guard session != nil else { return }
        if let message = engine.localTransform(transform, now: Self.now) {
            send(message, via: unreliable)
        }
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: Self.transformFlushDelay)
            guard !Task.isCancelled, let self,
                  let message = self.engine.flushTransform(now: Self.now) else { return }
            self.send(message, via: self.reliable)
        }
    }

    /// Nearby shared coordinate space (ARKit). Only meaningful while an
    /// ImmersiveSpace is open; call from the immersive scene.
    func startSharedCoordinateSpace() async throws {
        guard session != nil, RadarSharedSpaceRelay.isSupported else { return }
        let relay = sharedSpace ?? RadarSharedSpaceRelay()
        relay.outbound = { [weak self] data, recipients in
            guard let self else { return }
            let message = RadarSyncMessage(stamp: self.engine.nextStamp(now: Self.now),
                                           payload: .coordinateSpace(data: data, recipients: recipients))
            self.send(message, via: self.reliable)
        }
        sharedSpace = relay
        try await relay.start()
    }

    func stopSharedCoordinateSpace() {
        sharedSpace?.stop()
        sharedSpace = nil
    }

    // MARK: - Session

    private func configure(_ newSession: GroupSession<RadarGroupActivity>) async {
        // tearDown alone would keep this device joined to the old session.
        if let session, session !== newSession { session.leave() }
        tearDown()
        // Fresh replica per session: the joiner adopts the group's state.
        engine = RadarSyncEngine()
        session = newSession
        let reliable = GroupSessionMessenger(session: newSession, deliveryMode: .reliable)
        let unreliable = GroupSessionMessenger(session: newSession, deliveryMode: .unreliable)
        self.reliable = reliable
        self.unreliable = unreliable

        if let coordinator = await newSession.systemCoordinator {
            var configuration = SystemCoordinator.Configuration()
            configuration.spatialTemplatePreference = .sideBySide
            configuration.supportsGroupImmersiveSpace = true
            coordinator.configuration = configuration
        }

        sessionTasks.append(Task { [weak self] in
            for await state in newSession.$state.values {
                guard let self else { return }
                switch state {
                case .joined:
                    self.isActive = true
                    let request = RadarSyncMessage(stamp: self.engine.nextStamp(now: Self.now),
                                                   payload: .requestState)
                    self.send(request, via: self.reliable)
                case .waiting:
                    break
                case .invalidated:
                    self.tearDown()
                    return
                @unknown default:
                    break
                }
            }
        })
        sessionTasks.append(Task { [weak self] in
            for await participants in newSession.$activeParticipants.values {
                guard let self else { return }
                self.participantCount = participants.count
                self.nearbyParticipantCount = participants.filter(\.isNearbyWithLocalParticipant).count
            }
        })
        for messenger in [reliable, unreliable] {
            sessionTasks.append(Task { [weak self] in
                for await (data, context) in messenger.messages(of: Data.self) {
                    guard let self else { return }
                    self.handle(data, from: context.source)
                }
            })
        }
        newSession.join()
    }

    private func handle(_ data: Data, from participant: Participant) {
        guard let message = RadarSyncCodec.decode(data),
              let action = engine.receive(message) else { return }
        switch action {
        case .applySelection(let hex):
            applySelection?(hex)
        case .applyTransform(let transform):
            remoteTransform = transform
            remoteTransformRevision &+= 1
        case .sendState:
            engine.seedSelection(currentSelection?())
            for message in engine.snapshot() {
                send(message, via: reliable, to: .only(participant))
            }
        case .coordinateSpace(let data, let recipients):
            sharedSpace?.receive(data: data, recipients: recipients)
        }
    }

    private func send(_ message: RadarSyncMessage,
                      via messenger: GroupSessionMessenger?,
                      to participants: Participants = .all) {
        guard let messenger, let data = try? RadarSyncCodec.encode(message) else { return }
        messenger.send(data, to: participants) { _ in }
    }

    private func tearDown() {
        sessionTasks.forEach { $0.cancel() }
        sessionTasks.removeAll()
        flushTask?.cancel()
        flushTask = nil
        stopSharedCoordinateSpace()
        session = nil
        reliable = nil
        unreliable = nil
        isActive = false
        participantCount = 0
        nearbyParticipantCount = 0
    }

    private static var now: TimeInterval { Date().timeIntervalSince1970 }
}
