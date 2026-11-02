import RealityKit
import SwiftUI

struct RadarVolumeView: View {
    @Environment(FlightStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.physicalMetrics) private var physicalMetrics
    @State private var sceneHolder = RadarSceneHolder()
    private var scene: RadarSceneController { sceneHolder.controller }
    /// Parent of `scene.root`; carries the table-size scale so the user's
    /// manipulation scale on `scene.root` stays independent.
    @State private var tableMount = Entity()
    /// Selected-aircraft label (ViewAttachmentComponent + billboard).
    @State private var labelEntity = Entity()
    /// Anchor for the flight card popover (PresentationComponent).
    @State private var cardEntity = Entity()
    @State private var showCard = false
    @State private var manipulationSubscription: EventSubscription?
    @State private var activateSubscription: EventSubscription?
    @State private var surfaces = RadarSurfaceFeed()
    /// Bumped while paused so stale aircraft still age out without network updates.
    @State private var ageTick = 0
    @State private var viewpoint: SquareAzimuth = .front
    @State private var appliedTableScale: Double?
    /// Last SharePlay table transform revision applied to `scene.root`.
    @State private var appliedRemoteTransformRevision = 0

    private static let pollingClient = "radar-volume"

    var body: some View {
        let volume = RadarVolumeSize.meters(tableScale: store.settings.tableScale)
        RealityView { content in
            configureEntities()
            tableMount.addChild(scene.root)
            content.add(tableMount)
            manipulationSubscription = content.subscribe(
                to: ManipulationEvents.DidUpdateTransform.self,
                on: scene.root
            ) { event in
                RadarTableManipulation.constrain(event.entity)
                store.sharePlay.localTableTransformChanged(RadarTableTransform(event.entity.transform))
            }
            // VoiceOver "activate" on an aircraft selects it, like a tap.
            activateSubscription = content.subscribe(to: AccessibilityEvents.Activate.self) { event in
                if let hex = RadarEntityHit.hex(for: event.entity) { store.selectedHex = hex }
            }
            update()
        } update: { _ in
            // SwiftUI tracks store accesses here, so this runs when aircraft,
            // settings, selection or the pause tick change. Motion between network
            // updates is per-frame in AircraftMotionSystem.
            _ = ageTick
            update()
        }
        .frame(width: physicalMetrics.convert(volume.width, from: .meters),
               height: physicalMetrics.convert(volume.height, from: .meters))
        .frame(depth: physicalMetrics.convert(volume.depth, from: .meters))
        .gesture(SpatialTapGesture().targetedToAnyEntity().onEnded { value in
            guard let hex = RadarEntityHit.hex(for: value.entity) else { return }
            if store.selectedHex == hex {
                showCard.toggle()
            } else {
                showCard = false
                store.selectedHex = hex
            }
        })
        .volumeBaseplateVisibility(.visible)
        // Room for the flight panel, which keeps its size on the smaller table.
        .preferredWindowClippingMargins(.all, physicalMetrics.convert(0.25, from: .meters))
        .supportedVolumeViewpoints(.all)
        .onVolumeViewpointChange { _, newValue in
            viewpoint = newValue.squareAzimuth
        }
        .ornament(attachmentAnchor: .scene(RadarViewpointLayout.ornamentAnchor(for: viewpoint))) {
            RadarOrnamentView()
                .rotation3DEffect(viewpoint.orientation)
        }
        // Hidden with the flight card, which would open behind it, and when a table
        // below 1× brings it down over the flight panel.
        .ornament(visibility: showCard || (store.selectedHex != nil && store.settings.tableScale < 1) ? .hidden : .automatic,
                  attachmentAnchor: .scene(RadarSharePlayLayout.ornamentAnchor(for: viewpoint))) {
            RadarSharePlayButton()
                .rotation3DEffect(viewpoint.orientation)
        }
        .radarSettingsPersistence()
        .onAppear {
            store.isVolumeOpen = true
            store.acquirePolling(Self.pollingClient)
        }
        .onDisappear {
            store.isVolumeOpen = false
            store.releasePolling(Self.pollingClient)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.acquirePolling(Self.pollingClient) }
            else if phase == .background { store.releasePolling(Self.pollingClient) }
        }
        .onChange(of: store.selectedHex) { _, _ in showCard = false }
        .task(id: store.isPaused) {
            // Live polling already refreshes the scene every few seconds.
            guard store.isPaused else { return }
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

    // MARK: - Scene

    private func configureEntities() {
        tableMount.name = "radar-table-mount"

        // Rotate around Y and scale the whole table by pinching its surface.
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

        labelEntity.name = "radar-selected-label"
        labelEntity.components.set(ViewAttachmentComponent(rootView: RadarFlightLabel(store: store) { showCard.toggle() }))
        labelEntity.components.set(BillboardComponent())

        cardEntity.name = "radar-flight-card"
        cardEntity.components.set(PresentationComponent(
            isPresented: $showCard,
            configuration: .popover(arrowEdge: .bottom),
            content: AircraftDetailView()
                .environment(store)
                .frame(width: 640)
                .padding()
        ))
    }

    private func update() {
        let now = Date()
        let flights = store.renderableAircraft(at: now)
        let ages = store.positionAges(at: now)
        applyTableScale()
        applyRemoteTableTransform()
        apply(flights: flights, ages: ages)
        attachSelectionEntities()
    }

    private func applyTableScale() {
        let scale = store.settings.tableScale
        guard appliedTableScale != scale else { return }
        scene.setMarkerHitScale(Float(max(1, 1 / scale)))
        let target = Transform(scale: SIMD3(repeating: RadarVolumeSize.mountScale(tableScale: scale)))
        if appliedTableScale == nil {
            tableMount.transform = target
        } else {
            tableMount.move(to: target, relativeTo: tableMount.parent, duration: 0.45, timingFunction: .easeInOut)
        }
        appliedTableScale = scale
    }

    /// Table yaw/scale/offset received from another SharePlay participant. The
    /// coordinator's engine already holds this value, so no echo is sent back.
    private func applyRemoteTableTransform() {
        let sharePlay = store.sharePlay
        guard sharePlay.remoteTransformRevision != appliedRemoteTransformRevision else { return }
        appliedRemoteTransformRevision = sharePlay.remoteTransformRevision
        guard let remote = sharePlay.remoteTransform else { return }
        scene.root.move(to: remote.transform, relativeTo: scene.root.parent, duration: 0.2, timingFunction: .easeOut)
    }

    private func apply(flights: [Aircraft], ages: [String: Double]) {
        // The table draws the display radius (radius × table size); the scene
        // controller only knows one radius, so hand it the already-grown range.
        let drawn = RadarVolumeSize.drawnSettings(store.settings)
        scene.buildBackground(radiusKilometers: drawn.radiusKilometers)
        scene.setMap(surfaces.mapSurface, revision: surfaces.mapRevision)
        scene.setClouds(surfaces.cloudSurface, revision: surfaces.cloudRevision)
        scene.reconcile(
            aircraft: flights,
            selectedHex: store.selectedHex,
            settings: drawn,
            ageByHex: ages
        )
        scene.updateSelectedTrail(
            points: store.tracks[store.selectedHex ?? ""] ?? [],
            selectedHex: store.selectedHex,
            revision: store.trackRevision,
            settings: drawn,
            visible: store.showTrails
        )
    }

    /// Only the selected aircraft carries a label and the card anchor.
    private func attachSelectionEntities() {
        guard let hex = store.selectedHex,
              let marker = scene.root.findEntity(named: RadarEntityHit.prefix + hex) else {
            labelEntity.removeFromParent()
            cardEntity.removeFromParent()
            return
        }
        for entity in [labelEntity, cardEntity] where entity.parent !== marker {
            marker.addChild(entity)
        }
        RadarFlightLabel.place(labelEntity, on: marker)
        let markerScale = max(0.001, marker.scale(relativeTo: nil).y)
        cardEntity.position = [0, 0.32 / markerScale, 0]
        cardEntity.setScale([1, 1, 1], relativeTo: nil)
    }
}

// MARK: - Pure helpers

/// Volume dimensions and the radius actually drawn for a given table size.
enum RadarVolumeSize {
    static let baseWidth = RadarSettings.baseTableWidthMeters * 4 / 3
    static let baseHeight = RadarSettings.baseTableWidthMeters
    static let baseDepth = RadarSettings.baseTableWidthMeters * 7 / 6

    static func meters(tableScale: Double) -> (width: Double, height: Double, depth: Double) {
        (baseWidth * tableScale, baseHeight * tableScale, baseDepth * tableScale)
    }

    /// Scale from scene units (`RadarVisualGeometry.tableWidth`) to the table's physical width.
    static func mountScale(tableScale: Double) -> Float {
        Float(RadarSettings.baseTableWidthMeters * tableScale / Double(RadarVisualGeometry.tableWidth))
    }

    /// Settings handed to the scene controller: radius already multiplied by the table size.
    static func drawnSettings(_ settings: RadarSettings) -> RadarSettings {
        var drawn = settings
        drawn.radiusKilometers = settings.displayRadiusKilometers
        drawn.tableScale = 1
        return drawn
    }
}

/// Resolves a tapped entity (marker, stem or any child) to its aircraft hex.
enum RadarEntityHit {
    static let prefix = "flight:"

    @MainActor static func hex(for entity: Entity) -> String? {
        var current: Entity? = entity
        while let candidate = current {
            if candidate.name.hasPrefix(prefix) {
                let hex = String(candidate.name.dropFirst(prefix.count))
                return hex.isEmpty ? nil : hex
            }
            current = candidate.parent
        }
        return nil
    }
}

/// Keeps the manipulated table level (yaw only), centred and within a sane scale.
enum RadarTableManipulation {
    static let scaleRange: ClosedRange<Float> = 0.6...1.25

    /// Projects any rotation onto the vertical axis.
    static func yawOnly(_ rotation: simd_quatf) -> simd_quatf {
        let forward = rotation.act([0, 0, 1])
        if forward.x * forward.x + forward.z * forward.z < 1e-6 {
            // Looking straight up/down: use the right axis instead.
            let right = rotation.act([1, 0, 0])
            let yaw = atan2(-right.z, right.x)
            return simd_quatf(angle: yaw, axis: [0, 1, 0])
        }
        let yaw = atan2(forward.x, forward.z)
        return simd_quatf(angle: yaw, axis: [0, 1, 0])
    }

    /// Uniform scale clamped to `scaleRange`.
    static func clampScale(_ scale: SIMD3<Float>) -> SIMD3<Float> {
        let uniform = (scale.x + scale.y + scale.z) / 3
        let value = uniform.isFinite ? min(scaleRange.upperBound, max(scaleRange.lowerBound, uniform)) : 1
        return SIMD3(repeating: value)
    }

    @MainActor static func constrain(_ entity: Entity) {
        entity.orientation = yawOnly(entity.orientation)
        entity.scale = clampScale(entity.scale)
        entity.position = .zero
    }
}

/// Limits of the table offset carried in SharePlay transforms.
enum RadarTableDrag {
    static let limitX: Float = 0.18
    static let limitY: Float = 0.25
}
