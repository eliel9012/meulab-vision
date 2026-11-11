import RealityKit
import SwiftUI

/// Content of `ImmersiveSpace(id: "radar-immersive")`: the same radar scene as the
/// volume, placed on a real table (plane anchor), floating at table height as a
/// fallback, at room scale, or following the selected aircraft.
struct ImmersiveRadarView: View {
    @Environment(FlightStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var state = ImmersiveRadarState.shared
    @State private var sceneHolder = RadarSceneHolder()
    private var scene: RadarSceneController { sceneHolder.controller }
    /// World-locked parent for floating / room / follow placements.
    @State private var worldRoot = Entity()
    /// Real table: horizontal plane classified `.table`, at least 60 × 60 cm.
    @State private var tableAnchor = AnchorEntity(
        .plane(.horizontal, classification: .table, minimumBounds: [0.6, 0.6]),
        trackingMode: .once
    )
    /// Carries placement + physical scale; `scene.root` keeps the user's yaw rotation.
    @State private var mount = Entity()
    @State private var controlsEntity = Entity()
    /// Panel of the selected aircraft (ViewAttachmentComponent + billboard).
    @State private var labelEntity = Entity()
    @State private var subscriptions: [EventSubscription] = []
    @State private var trackingSession: SpatialTrackingSession?
    @State private var surfaces = RadarSurfaceFeed()
    @State private var ageTick = 0
    @State private var appliedRemoteTransformRevision = 0

    private static let pollingClient = "immersive"

    var body: some View {
        RealityView { content in
            configureEntities()
            content.add(worldRoot)
            content.add(tableAnchor)
            subscriptions = [
                content.subscribe(to: AnchorStateEvents.DidAnchor.self, on: tableAnchor) { _ in
                    state.isAnchoredToTable = true
                },
                content.subscribe(to: AnchorStateEvents.WillUnanchor.self, on: tableAnchor) { _ in
                    state.isAnchoredToTable = false
                },
                content.subscribe(to: ManipulationEvents.DidUpdateTransform.self, on: scene.root) { event in
                    RadarTableManipulation.constrain(event.entity)
                    store.sharePlay.localTableTransformChanged(RadarTableTransform(event.entity.transform))
                },
                content.subscribe(to: AccessibilityEvents.Activate.self) { event in
                    if let hex = RadarEntityHit.hex(for: event.entity) { store.selectedHex = hex }
                },
                content.subscribe(to: SceneEvents.Update.self) { event in
                    followSelectedAircraft(deltaTime: Float(event.deltaTime))
                }
            ]
            scene.applyEnvironmentOcclusion(true)
            update()
        } update: { _ in
            _ = ageTick
            _ = state.placement
            _ = state.scale
            update()
        }
        .gesture(SpatialTapGesture().targetedToAnyEntity().onEnded { value in
            guard let hex = RadarEntityHit.hex(for: value.entity) else { return }
            store.selectedHex = store.selectedHex == hex ? nil : hex
        })
        .radarSettingsPersistence()
        .onAppear {
            state.isOpen = true
            store.acquirePolling(Self.pollingClient)
        }
        .onDisappear {
            state.isOpen = false
            state.isAnchoredToTable = false
            state.setFollow(false)
            store.releasePolling(Self.pollingClient)
            store.sharePlay.stopSharedCoordinateSpace()
            if let session = trackingSession {
                trackingSession = nil
                Task { await session.stop() }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.acquirePolling(Self.pollingClient) }
            else if phase == .background { store.releasePolling(Self.pollingClient) }
        }
        .onChange(of: store.selectedHex) { _, hex in
            if hex == nil, state.followSelected { state.setFollow(false) }
        }
        .task { await startPlaneTracking() }
        .task(id: store.sharePlay.isActive) {
            guard store.sharePlay.isActive else { return }
            try? await store.sharePlay.startSharedCoordinateSpace()
        }
        .task(id: store.needsAgeTick) {
            // Live polling already refreshes the scene every few seconds.
            guard store.needsAgeTick else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                ageTick &+= 1
            }
        }
        .task(id: "\(store.settings.displayRadiusKilometers)-\(store.mapStyle.rawValue)") {
            await surfaces.loadMap(radiusKilometers: store.settings.displayRadiusKilometers, style: store.mapStyle)
        }
        .task(id: "\(store.settings.displayRadiusKilometers)-\(store.showClouds)") {
            await surfaces.loadClouds(radiusKilometers: store.settings.displayRadiusKilometers,
                                      enabled: store.showClouds, store: store)
        }
    }

    // MARK: - Setup

    private func configureEntities() {
        worldRoot.name = "radar-immersive-world"
        worldRoot.components.set(RadarPingAudio.roomReverb())
        mount.name = "radar-immersive-mount"
        mount.addChild(scene.root)

        // Yaw-only rotation: the way to align the model's red north marker with the
        // real north (visionOS exposes no compass heading to apps).
        var manipulation = ManipulationComponent()
        manipulation.dynamics.translationBehavior = .none
        manipulation.dynamics.primaryRotationBehavior = .unconstrained
        manipulation.dynamics.secondaryRotationBehavior = .none
        manipulation.dynamics.scalingBehavior = .unconstrained
        manipulation.dynamics.inertia = .low
        manipulation.releaseBehavior = .stay
        scene.root.components.set(manipulation)
        scene.root.components.set(InputTargetComponent())
        scene.tableSurface.components.set(ManipulationComponent.HitTarget(redirectedEntity: scene.root))

        controlsEntity.name = "radar-immersive-controls"
        controlsEntity.components.set(ViewAttachmentComponent(
            rootView: ImmersiveRadarControls().environment(store)
        ))
        controlsEntity.components.set(BillboardComponent())
        worldRoot.addChild(controlsEntity)

        labelEntity.name = "radar-selected-label"
        labelEntity.components.set(ViewAttachmentComponent(rootView: RadarFlightLabel(store: store)))
        labelEntity.components.set(BillboardComponent())
    }

    private func startPlaneTracking() async {
        guard trackingSession == nil else { return }
        let session = SpatialTrackingSession()
        trackingSession = session
        let unavailable = await session.run(.init(tracking: [.plane]))
        // Denied world sensing or simulator: stay on the floating fallback.
        state.planeTrackingUnavailable = unavailable?.anchor.contains(.plane) ?? false
    }

    // MARK: - Update

    private func applyRemoteTableTransform() {
        let sharePlay = store.sharePlay
        guard sharePlay.remoteTransformRevision != appliedRemoteTransformRevision else { return }
        appliedRemoteTransformRevision = sharePlay.remoteTransformRevision
        guard let remote = sharePlay.remoteTransform else { return }
        scene.root.move(to: remote.transform, relativeTo: scene.root.parent, duration: 0.2, timingFunction: .easeOut)
    }

    private func update() {
        applyPlacement()
        applyRemoteTableTransform()
        let now = Date()
        let flights = store.renderableAircraft(at: now)
        let ages = store.positionAges(at: now)
        let drawn = RadarVolumeSize.drawnSettings(store.settings)
        scene.buildBackground(radiusKilometers: drawn.radiusKilometers)
        scene.setMap(surfaces.mapSurface, revision: surfaces.mapRevision)
        scene.setClouds(surfaces.cloudSurface, revision: surfaces.cloudRevision)
        scene.reconcile(aircraft: flights, selectedHex: store.selectedHex, settings: drawn, ageByHex: ages)
        scene.updateSelectedTrail(
            points: store.tracks[store.selectedHex ?? ""] ?? [],
            selectedHex: store.selectedHex,
            revision: store.trackRevision,
            settings: drawn,
            visible: store.showTrails
        )
        if let hex = store.selectedHex, let marker = scene.markerEntity(for: hex) {
            if labelEntity.parent !== marker { marker.addChild(labelEntity) }
            RadarFlightLabel.place(labelEntity, on: marker)
        } else {
            labelEntity.removeFromParent()
        }
    }

    /// Reparents / scales the mount for the current placement. Follow mode position
    /// is animated per frame in `followSelectedAircraft`.
    private func applyPlacement() {
        let placement = state.placement
        let scale = state.scale
        let parent: Entity = placement == .table ? tableAnchor : worldRoot
        if mount.parent !== parent {
            parent.addChild(mount)
        }
        mount.scale = SIMD3(repeating: scale)
        if placement != .following {
            mount.position = ImmersiveRadarLayout.mountPosition(for: placement, scale: scale)
        } else if mount.parent == nil || mount.position == .zero {
            mount.position = ImmersiveRadarLayout.mountPosition(for: .floating, scale: scale)
        }
        // Controls float beside the radar (or near the user in room mode).
        controlsEntity.position = switch placement {
        case .room: [0.55, 1.1, -0.9]
        default: [0.6, 1.05, -0.9]
        }
    }

    private func followSelectedAircraft(deltaTime: Float) {
        guard state.followSelected, mount.parent === worldRoot,
              let hex = store.selectedHex,
              let marker = scene.markerEntity(for: hex) else { return }
        let local = marker.position(relativeTo: mount)
        let goal = ImmersiveRadarLayout.followMountPosition(
            markerLocal: local, scale: mount.scale.x, rotation: mount.orientation
        )
        mount.position = ImmersiveRadarLayout.smoothed(mount.position, toward: goal, deltaTime: deltaTime)
    }
}

/// Floating control panel inside the immersive space.
struct ImmersiveRadarControls: View {
    @Environment(FlightStore.self) private var store
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @State private var state = ImmersiveRadarState.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Modo", selection: $state.mode) {
                ForEach(ImmersiveRadarMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if state.mode == .room {
                Stepper(value: $state.roomWidthMeters, in: ImmersiveRadarLayout.roomWidthRange, step: 0.5) {
                    Text("Sala \(RadarSettings.metersLabel(state.roomWidthMeters))")
                }
            }

            Toggle("Seguir avião", isOn: Binding(
                get: { state.followSelected },
                set: { state.setFollow($0) }
            ))
            .disabled(store.selectedHex == nil)

            Toggle("Som espacial", isOn: Binding(
                get: { store.settings.spatialAudioEnabled },
                set: { store.settings.spatialAudioEnabled = $0 }
            ))

            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Fechar imersivo", systemImage: "xmark") {
                Task { await dismissImmersiveSpace() }
            }
        }
        .padding(20)
        .frame(width: 340)
        .glassBackgroundEffect()
    }

    private var statusText: String {
        switch state.placement {
        case .table: "Na mesa. Gire o radar para alinhar o norte (marcador vermelho)."
        case .floating where state.planeTrackingUnavailable: "Sem detecção de mesa: radar flutuando à frente."
        case .floating: "Procurando mesa… radar flutuando à frente."
        case .room: "Escala de sala. O norte é o do modelo; gire para alinhar."
        case .following: "Seguindo o avião selecionado."
        }
    }
}
