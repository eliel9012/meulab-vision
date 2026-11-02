import Foundation
import RealityKit
import UIKit
import simd

/// Shared, immutable materials. Built once instead of on every update.
@MainActor
enum RadarMaterials {
    static let edge = SimpleMaterial(color: UIColor.cyan.withAlphaComponent(0.45), isMetallic: true)
    static let outerRing = SimpleMaterial(color: UIColor.cyan.withAlphaComponent(0.9), isMetallic: false)
    static let innerRing = SimpleMaterial(color: UIColor.white.withAlphaComponent(0.5), isMetallic: false)
    static let trail = SimpleMaterial(color: UIColor.cyan.withAlphaComponent(0.75), isMetallic: false)
    static let northMarker = SimpleMaterial(color: .systemRed, isMetallic: false)
    static let antenna = SimpleMaterial(color: .systemBlue, isMetallic: true)
    static let terrainFallback = SimpleMaterial(color: UIColor.systemGray2, isMetallic: false)
    static let stemNormal = SimpleMaterial(color: UIColor.systemBlue.withAlphaComponent(0.65), isMetallic: false)
    static let stemSelected = SimpleMaterial(color: UIColor.cyan.withAlphaComponent(0.65), isMetallic: false)
    static let stemAging = SimpleMaterial(color: UIColor.systemOrange.withAlphaComponent(0.65), isMetallic: false)

    static func stem(_ state: RadarMarkerState) -> SimpleMaterial {
        switch state {
        case .normal: stemNormal
        case .selected: stemSelected
        case .aging: stemAging
        }
    }
}

/// Visual state of an aircraft marker; selection wins over aging.
enum RadarMarkerState: Equatable, Sendable {
    case normal, selected, aging

    init(selected: Bool, aging: Bool) {
        self = selected ? .selected : (aging ? .aging : .normal)
    }
}

/// `@State` evaluates its initial value on every view init and drops all but the first,
/// so the views keep this cheap holder and build the controller once, on first use.
@MainActor
final class RadarSceneHolder {
    lazy var controller = RadarSceneController()
}

/// Keeps a stable scene graph and reconciles entities incrementally by ICAO/hex.
/// Ranges are drawn with `RadarSettings.displayRadiusKilometers`; the visual table radius
/// stays constant in scene units (the view scales `root` by `tableScale`).
@MainActor
final class RadarSceneController {
    let root = Entity()
    let tableSurface = ModelEntity(
        mesh: .generateBox(size: [RadarVisualGeometry.tableWidth, 0.024, RadarVisualGeometry.tableWidth]),
        materials: [SimpleMaterial(color: UIColor.white.withAlphaComponent(0.14), isMetallic: false)]
    )
    private let background = Entity()
    private let markerLayer = Entity()
    private let trailLayer = Entity()
    private let factory = AircraftEntityFactory()
    private var markers: [String: Entity] = [:]
    private var markerStates: [String: RadarMarkerState] = [:]
    private var terrainSurface: Entity?
    private var cloudSurface: ModelEntity?
    private var lastMapSurface: RadarMapSurface?
    private var lastCloudSurface: RadarCloudSurface?
    private var currentRadius: Double = -1
    private var currentTableScale: Double = 1
    private var currentMapRevision = -1
    private var currentCloudRevision = -1
    private var currentTrailKey = ""
    private var currentThermalState = ProcessInfo.processInfo.thermalState
    private let groundY = RadarVisualGeometry.groundY
    private let visualRadius = RadarVisualGeometry.mapRadius
    /// Terrain switches to the coarse grid beyond this camera distance (metres).
    static let terrainDetailDistance: Float = 2.5
    static let terrainLowResolution = 33

    init() {
        AircraftMotionSystem.registerOnce()
        root.name = "radar-root"
        background.name = "radar-background"
        tableSurface.name = "radar-table"
        tableSurface.position = [0, groundY - 0.012, 0]
        tableSurface.components.set(InputTargetComponent())
        tableSurface.components.set(CollisionComponent(shapes: [.generateBox(size: [RadarVisualGeometry.tableWidth, 0.03, RadarVisualGeometry.tableWidth])]))
        tableSurface.components.set(GroundingShadowComponent(castsShadow: false, receivesShadow: true))
        root.addChild(background)
        root.addChild(tableSurface)
        root.addChild(trailLayer)
        root.addChild(markerLayer)
    }

    func setMarkerHitScale(_ scale: Float) {
        guard scale != factory.hitScale else { return }
        factory.hitScale = scale
        for marker in markers.values { factory.applyHitShape(to: marker) }
    }

    /// Range actually drawn on the table (km); -1 before the first build.
    var displayRadiusKilometers: Double { currentRadius }

    /// Preferred entry point: draws `settings.displayRadiusKilometers`.
    func buildBackground(settings: RadarSettings) {
        currentTableScale = settings.tableScale
        buildBackground(displayRadiusKilometers: settings.displayRadiusKilometers)
    }

    /// Legacy entry point: `radiusKilometers` is the selected radius; it is grown by the
    /// last known `tableScale` (from `buildBackground(settings:)` or `reconcile`).
    func buildBackground(radiusKilometers: Double) {
        buildBackground(displayRadiusKilometers: radiusKilometers * currentTableScale)
    }

    func buildBackground(displayRadiusKilometers radius: Double) {
        guard radius.isFinite, radius > 0, radius != currentRadius else { return }
        currentRadius = radius
        // Not `forEach { removeFromParent() }`: that mutates the collection mid-walk and skips entities.
        background.children.removeAll()
        terrainSurface = nil
        cloudSurface = nil

        // Table edges: one mesh.
        let halfTable = RadarVisualGeometry.tableWidth / 2
        var edges = RadarMeshBatch()
        for x in [-halfTable, halfTable] {
            edges.addBox(size: [0.004, 0.026, RadarVisualGeometry.tableWidth], .init(translation: [x, groundY - 0.01, 0]))
        }
        for z in [-halfTable, halfTable] {
            edges.addBox(size: [RadarVisualGeometry.tableWidth, 0.026, 0.004], .init(translation: [0, groundY - 0.01, z]))
        }
        addMesh([edges], materials: [RadarMaterials.edge], name: "radar-edges")

        // Range rings: one mesh, inner rings in part 0, outer ring in part 1.
        var inner = RadarMeshBatch(), outer = RadarMeshBatch()
        for fraction in [Float(0.25), Float(0.5), Float(0.75), Float(1.0)] {
            let points = ringPoints(radius: visualRadius * fraction, segments: 48)
            if fraction == 1 {
                outer.addPolylineTube(points, width: 0.0028, height: 0.0028, closed: true)
            } else {
                inner.addPolylineTube(points, width: 0.0015, height: 0.0015, closed: true)
            }
        }
        addMesh([inner, outer], materials: [RadarMaterials.innerRing, RadarMaterials.outerRing], name: "radar-rings")

        // North marker (not an absolute compass reading of the physical room).
        let north = ModelEntity(mesh: .generateBox(size: [0.014, 0.003, 0.026]), materials: [RadarMaterials.northMarker])
        north.position = [0, surfaceY(x: 0, z: -visualRadius) + 0.012, -visualRadius]
        background.addChild(north)
        let antenna = ModelEntity(mesh: .generateSphere(radius: 0.009), materials: [RadarMaterials.antenna])
        antenna.position = [0, surfaceY(x: 0, z: 0) + 0.014, 0]
        antenna.components.set(GroundingShadowComponent(castsShadow: true, receivesShadow: false))
        background.addChild(antenna)

        // Terrain and clouds depend on the radius. Rebuilt from the last surfaces; the
        // surface feed clears those as soon as the radius changes, then delivers new ones.
        buildTerrain(lastMapSurface)
        buildClouds(lastCloudSurface)
        applyOcclusionIfEnabled(to: background)

        // Aircraft must jump to their new scaled positions, not glide there.
        for marker in markers.values {
            guard var motion = marker.components[AircraftMotionComponent.self] else { continue }
            motion.displayRadiusKilometers = radius
            motion.needsSnap = true
            marker.components.set(motion)
            place(marker, motion: motion)
        }
        currentTrailKey = ""
    }

    func setMap(_ surface: RadarMapSurface?, revision: Int) {
        guard currentMapRevision != revision else { return }
        currentMapRevision = revision
        lastMapSurface = surface
        guard currentRadius > 0 else { return }
        buildTerrain(surface)
        if let terrainSurface { applyOcclusionIfEnabled(to: terrainSurface) }
    }

    func setClouds(_ surface: RadarCloudSurface?, revision: Int) {
        guard currentCloudRevision != revision else { return }
        currentCloudRevision = revision
        lastCloudSurface = surface
        guard currentRadius > 0 else { return }
        buildClouds(surface)
        if let cloudSurface { applyOcclusionIfEnabled(to: cloudSurface) }
    }

    func reconcile(aircraft: [Aircraft], selectedHex: String?, settings: RadarSettings, ageByHex: [String: Double]) {
        currentTableScale = settings.tableScale
        buildBackground(displayRadiusKilometers: settings.displayRadiusKilometers)
        let thermal = ProcessInfo.processInfo.thermalState
        let thermalChanged = thermal != currentThermalState
        currentThermalState = thermal

        let newIDs = Set(aircraft.map(\.hex))
        for key in Array(markers.keys) where !newIDs.contains(key) {
            markers.removeValue(forKey: key)?.removeFromParent()
            markerStates.removeValue(forKey: key)
        }

        let now = Date().timeIntervalSinceReferenceDate
        for flight in aircraft {
            guard let lat = flight.latitude, let lon = flight.longitude else { continue }
            let altitude = flight.altitudeMeters ?? 0
            let age = max(0, ageByHex[flight.hex] ?? 0)
            var motion = AircraftMotionComponent(
                latitude: lat, longitude: lon,
                altitudeMeters: altitude,
                horizontalAltitudeMeters: flight.geometricAltitudeMeters ?? altitude,
                groundSpeedKnots: flight.speedKnots ?? 0,
                trackDegrees: flight.trackDegrees ?? 0,
                baroRateFeetPerMinute: flight.verticalRateFeetPerMinute ?? 0,
                timestamp: now - age,
                displayRadiusKilometers: currentRadius,
                verticalExaggeration: settings.verticalExaggeration,
                isOnGround: flight.altitudeKind == .ground
            )
            let entity: Entity
            if let existing = markers[flight.hex] {
                entity = existing
                let previous = existing.components[AircraftMotionComponent.self]
                motion.needsSnap = previous?.needsSnap ?? true
                    || previous?.verticalExaggeration != motion.verticalExaggeration
                if thermalChanged { AircraftEntityFactory.applyThermalState(thermal, to: entity) }
            } else {
                entity = factory.make(aircraft: flight)
                markers[flight.hex] = entity
                markerLayer.addChild(entity)
                applyOcclusionIfEnabled(to: entity)
            }
            entity.components.set(motion)
            if motion.needsSnap { place(entity, motion: motion, at: now) }
            factory.updateAccessibility(entity, aircraft: flight)

            let isAging = age > 15
            let isSelected = flight.hex == selectedHex
            let state = RadarMarkerState(selected: isSelected, aging: isAging)
            // Reassign materials only when the visual state actually changes.
            if markerStates[flight.hex] != state {
                markerStates[flight.hex] = state
                factory.restyle(entity, selected: isSelected, aging: isAging)
                if let motion = entity.components[AircraftMotionComponent.self],
                   let target = motion.visualTarget(at: now) {
                    AircraftMotionSystem.updateStem(of: entity, terrainY: target.terrainY)
                }
            }
        }
        if thermalChanged, let terrainSurface {
            applyTerrainThermalState(thermal, to: terrainSurface)
        }
        evaluatePing(aircraft: aircraft, selectedHex: selectedHex, settings: settings)
    }

    // MARK: - Fase 5A: spatial audio + occlusion

    /// New-aircraft / selection detection for the spatial ping (per scene).
    private var pingPolicy = RadarPingPolicy()
    /// Set by the immersive space: markers get `EnvironmentBlendingComponent`.
    private(set) var occlusionEnabled = false

    private func evaluatePing(aircraft: [Aircraft], selectedHex: String?, settings: RadarSettings) {
        let visible = aircraft.compactMap { $0.latitude != nil && $0.longitude != nil ? $0.hex : nil }
        // Always advance the policy so toggling sound on later doesn't ping a backlog.
        guard let event = pingPolicy.event(visibleHexes: visible, selectedHex: selectedHex),
              settings.spatialAudioEnabled,
              let entity = markers[event.hex] else { return }
        RadarPingPlayer.shared.play(event, on: entity)
    }

    /// Plays the spatial ping on an aircraft marker now (still globally throttled).
    func ping(hex: String, selected: Bool) {
        guard let entity = markers[hex] else { return }
        RadarPingPlayer.shared.play(selected ? .selected(hex) : .appeared(hex), on: entity)
    }

    /// Makes real-world surfaces (people, furniture) occlude the radar. Only meaningful in
    /// an ImmersiveSpace; volumes are always composited above the room.
    func applyEnvironmentOcclusion(_ enabled: Bool) {
        occlusionEnabled = enabled
        RadarOcclusion.apply(enabled, to: root)
    }

    /// Entities created after `applyEnvironmentOcclusion` get it here, without walking the whole tree.
    private func applyOcclusionIfEnabled(to entity: Entity) {
        if occlusionEnabled { RadarOcclusion.apply(true, to: entity) }
    }

    func updateSelectedTrail(points: [FlightTrackPoint], selectedHex: String?, revision: Int,
                             settings: RadarSettings, visible: Bool) {
        let radius = settings.displayRadiusKilometers
        let key = "\(selectedHex ?? "")-\(revision)-\(radius)-\(settings.verticalExaggeration)-\(visible)"
        guard key != currentTrailKey else { return }
        currentTrailKey = key
        trailLayer.children.removeAll()
        guard visible, points.count >= 2 else { return }
        let positions: [SIMD3<Float>] = points.compactMap { point in
            let coordinate = GeodeticCoordinate(latitudeDegrees: point.latitude,
                                                longitudeDegrees: point.longitude,
                                                altitudeMeters: point.altitudeMeters)
            let enu = Geodesy.enu(coordinate, relativeTo: Geodesy.approximateFranca)
            guard enu.horizontalDistanceMeters <= radius * 1_000,
                  let visual = Geodesy.visualPosition(
                    enu: enu, displayedAltitudeMeters: point.altitudeMeters,
                    radiusKilometers: radius,
                    verticalExaggeration: settings.verticalExaggeration
                  ) else { return nil }
            let x = Float(visual.x), z = Float(visual.z)
            return [x, max(Float(visual.y), surfaceY(x: x, z: z, radiusKilometers: radius) + 0.018), z]
        }
        var trail = RadarMeshBatch()
        trail.addPolylineTube(positions, width: 0.0018, height: 0.0018, closed: false)
        guard !trail.isEmpty, let mesh = try? RadarMeshBatch.meshResource([trail], name: "trail") else { return }
        let entity = ModelEntity(mesh: mesh, materials: [RadarMaterials.trail])
        entity.name = "radar-trail"
        trailLayer.addChild(entity)
        applyOcclusionIfEnabled(to: entity)
    }

    var markerCount: Int { markers.count }

    func markerPosition(for hex: String) -> SIMD3<Float>? { markers[hex]?.position }

    /// Marker entity for a hex (labels can be parented to it to follow per-frame motion).
    func markerEntity(for hex: String) -> Entity? { markers[hex] }

    /// Hex of the aircraft that owns a tapped/hovered entity.
    static func hex(for entity: Entity) -> String? { AircraftEntityFactory.hex(for: entity) }

    // MARK: - Private

    private func place(_ entity: Entity, motion: AircraftMotionComponent,
                       at now: TimeInterval = Date().timeIntervalSinceReferenceDate) {
        guard let target = motion.visualTarget(at: now) else { return }
        entity.position = target.position
        let track = Float(motion.trackDegrees) * .pi / 180
        entity.orientation = simd_quatf(angle: -track, axis: [0, 1, 0])
        AircraftMotionSystem.updateStem(of: entity, terrainY: target.terrainY)
    }

    private func addMesh(_ batches: [RadarMeshBatch], materials: [any Material], name: String) {
        guard let mesh = try? RadarMeshBatch.meshResource(batches, name: name) else { return }
        let entity = ModelEntity(mesh: mesh, materials: materials)
        entity.name = name
        background.addChild(entity)
    }

    private func ringPoints(radius: Float, segments: Int) -> [SIMD3<Float>] {
        (0..<segments).map { i in
            let a = Float(i) * 2 * .pi / Float(segments)
            let x = radius * cos(a), z = radius * sin(a)
            return [x, surfaceY(x: x, z: z) + 0.005, z]
        }
    }

    private func buildTerrain(_ surface: RadarMapSurface?) {
        terrainSurface?.removeFromParent()
        terrainSurface = nil
        if let terrain = RadarTerrain.shared {
            let textureCoordinates = surface?.textureCoordinates
            guard let detailMesh = try? terrain.mesh(radiusKilometers: currentRadius,
                                                     textureCoordinates: textureCoordinates) else { return }
            let lowMesh = try? terrain.mesh(radiusKilometers: currentRadius, textureCoordinates: textureCoordinates,
                                            resolution: Self.terrainLowResolution)
            let material: any Material
            if let surface {
                var mapped = PhysicallyBasedMaterial()
                mapped.baseColor = .init(tint: .white, texture: .init(surface.texture))
                mapped.roughness = 0.85
                material = mapped
            } else {
                material = RadarMaterials.terrainFallback
            }
            let container = Entity()
            container.name = "franca-terrain"
            let detail = ModelEntity(mesh: detailMesh, materials: [material])
            detail.name = "franca-terrain-detail"
            detail.components.set(GroundingShadowComponent(castsShadow: false, receivesShadow: true))
            container.addChild(detail)
            if let lowMesh {
                let low = ModelEntity(mesh: lowMesh, materials: [material])
                low.name = "franca-terrain-low"
                low.components.set(GroundingShadowComponent(castsShadow: false, receivesShadow: true))
                container.addChild(low)
                LevelOfDetailComponent.addByCameraDistance(to: container, levels: [
                    (entities: [detail], maxDistance: Self.terrainDetailDistance),
                    (entities: [low], maxDistance: .greatestFiniteMagnitude)
                ])
                applyTerrainThermalState(currentThermalState, to: container)
            }
            background.addChild(container)
            terrainSurface = container
        } else if let surface {
            let plane = ModelEntity(
                mesh: .generatePlane(width: visualRadius * 2, depth: visualRadius * 2),
                materials: [UnlitMaterial(texture: surface.texture)]
            )
            plane.name = "franca-terrain"
            plane.position = [0, groundY + 0.002, 0]
            plane.components.set(GroundingShadowComponent(castsShadow: false, receivesShadow: true))
            background.addChild(plane)
            terrainSurface = plane
        }
    }

    private func applyTerrainThermalState(_ state: ProcessInfo.ThermalState, to entity: Entity) {
        guard var lod = entity.components[LevelOfDetailComponent.self] else { return }
        lod.levelSelection = (state == .serious || state == .critical) ? .fixed(1) : .automatic
        entity.components.set(lod)
    }

    private func buildClouds(_ surface: RadarCloudSurface?) {
        cloudSurface?.removeFromParent()
        cloudSurface = nil
        guard let surface, let terrain = RadarTerrain.shared,
              let mesh = try? terrain.mesh(radiusKilometers: currentRadius,
                                           textureCoordinates: surface.textureCoordinates,
                                           verticalOffset: 0.007) else { return }
        let entity = ModelEntity(mesh: mesh, materials: [Self.cloudMaterial(surface.texture)])
        entity.name = "goes-east-infrared"
        background.addChild(entity)
        cloudSurface = entity
    }

    /// Unlit, translucent cloud layer so terrain and aircraft shadows read through it.
    static func cloudMaterial(_ texture: TextureResource) -> UnlitMaterial {
        var material = UnlitMaterial(texture: texture)
        material.blending = .transparent(opacity: .init(floatLiteral: 0.85))
        return material
    }

    private func surfaceY(x: Float, z: Float) -> Float {
        surfaceY(x: x, z: z, radiusKilometers: currentRadius)
    }

    private func surfaceY(x: Float, z: Float, radiusKilometers: Double) -> Float {
        guard let terrain = RadarTerrain.shared, radiusKilometers > 0 else { return groundY }
        return terrain.surfaceY(x: x, z: z, radiusKilometers: radiusKilometers)
    }
}
