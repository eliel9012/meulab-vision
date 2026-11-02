import Foundation
import RealityKit
import simd

/// Last known kinematic state of an aircraft, refreshed on every network update.
/// `AircraftMotionSystem` dead-reckons from it every rendered frame.
struct AircraftMotionComponent: Component {
    var latitude: Double
    var longitude: Double
    var altitudeMeters: Double
    /// Altitude used for the horizontal ENU projection (geometric when known).
    var horizontalAltitudeMeters: Double
    var groundSpeedKnots: Double
    var trackDegrees: Double
    var baroRateFeetPerMinute: Double
    /// `Date.timeIntervalSinceReferenceDate` of the position fix.
    var timestamp: TimeInterval
    var displayRadiusKilometers: Double
    var verticalExaggeration: Double
    var isOnGround: Bool
    /// Jump straight to the target on the next frame (new marker or range change).
    var needsSnap = true

    /// Dead reckoning never runs past this horizon; stale data freezes instead of drifting.
    static let maximumExtrapolationSeconds: Double = 30

    struct Extrapolated: Equatable, Sendable {
        var latitude: Double
        var longitude: Double
        var altitudeMeters: Double
    }

    /// Pure great-circle-free (flat earth, local) dead reckoning. Accurate to metres
    /// over the 30 s horizon, which is far below one rendered pixel on the table.
    static func extrapolate(latitude: Double, longitude: Double, altitudeMeters: Double,
                            groundSpeedKnots: Double, trackDegrees: Double,
                            baroRateFeetPerMinute: Double, isOnGround: Bool,
                            elapsed: Double) -> Extrapolated {
        let dt = min(maximumExtrapolationSeconds, max(0, elapsed.isFinite ? elapsed : 0))
        let speed = groundSpeedKnots.isFinite ? max(0, groundSpeedKnots) * 1_852 / 3_600 : 0
        let distance = speed * dt
        let track = (trackDegrees.isFinite ? trackDegrees : 0) * .pi / 180
        let north = distance * cos(track)
        let east = distance * sin(track)
        let earthRadius = 6_371_000.0
        let latitudeRadians = latitude * .pi / 180
        let newLatitude = latitude + north / earthRadius * 180 / .pi
        let cosLatitude = max(1e-6, cos(latitudeRadians))
        let newLongitude = longitude + east / (earthRadius * cosLatitude) * 180 / .pi
        var newAltitude = altitudeMeters
        if !isOnGround, baroRateFeetPerMinute.isFinite {
            newAltitude = max(0, altitudeMeters + baroRateFeetPerMinute * 0.3048 / 60 * dt)
        }
        return .init(latitude: newLatitude, longitude: newLongitude, altitudeMeters: newAltitude)
    }

    func extrapolated(at now: TimeInterval) -> Extrapolated {
        Self.extrapolate(latitude: latitude, longitude: longitude, altitudeMeters: altitudeMeters,
                         groundSpeedKnots: groundSpeedKnots, trackDegrees: trackDegrees,
                         baroRateFeetPerMinute: baroRateFeetPerMinute, isOnGround: isOnGround,
                         elapsed: now - timestamp)
    }

    /// Table-space position (root of the radar scene) for the extrapolated state,
    /// clamped above the terrain. Returns the terrain height too, for the stem.
    func visualTarget(at now: TimeInterval) -> (position: SIMD3<Float>, terrainY: Float)? {
        let state = extrapolated(at: now)
        let horizontalAltitude = horizontalAltitudeMeters + (state.altitudeMeters - altitudeMeters)
        let enu = Geodesy.enu(.init(latitudeDegrees: state.latitude, longitudeDegrees: state.longitude,
                                    altitudeMeters: horizontalAltitude),
                              relativeTo: Geodesy.approximateFranca)
        guard let visual = Geodesy.visualPosition(enu: enu, displayedAltitudeMeters: state.altitudeMeters,
                                                  radiusKilometers: displayRadiusKilometers,
                                                  verticalExaggeration: verticalExaggeration) else { return nil }
        let x = Float(visual.x), z = Float(visual.z)
        let terrainY = RadarTerrain.shared?.surfaceY(x: x, z: z, radiusKilometers: displayRadiusKilometers)
            ?? RadarVisualGeometry.groundY
        return ([x, max(Float(visual.y), terrainY + 0.016), z], terrainY)
    }
}

/// Moves every aircraft between network updates so motion looks continuous at 90 Hz.
@MainActor
struct AircraftMotionSystem: System {
    private static let query = EntityQuery(where: .has(AircraftMotionComponent.self))
    private static var registered = false

    /// Registers the component and the system exactly once per process.
    static func registerOnce() {
        guard !registered else { return }
        registered = true
        AircraftMotionComponent.registerComponent()
        registerSystem()
    }

    init(scene: Scene) {}

    mutating func update(context: SceneUpdateContext) {
        let now = Date().timeIntervalSinceReferenceDate
        let dt = Float(max(0, min(0.25, context.deltaTime)))
        // Critically damped follow: hides the small jump when a fresh fix arrives.
        let blend = 1 - exp(-dt * 6)
        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            guard var motion = entity.components[AircraftMotionComponent.self],
                  let target = motion.visualTarget(at: now) else { continue }
            if motion.needsSnap {
                entity.position = target.position
                motion.needsSnap = false
                entity.components.set(motion)
            } else {
                entity.position = simd_mix(entity.position, target.position, SIMD3(repeating: blend))
            }
            let track = Float(motion.trackDegrees.isFinite ? motion.trackDegrees : 0) * .pi / 180
            entity.orientation = simd_quatf(angle: -track, axis: [0, 1, 0])
            Self.updateStem(of: entity, terrainY: target.terrainY)
        }
    }

    /// The stem is a child; undo the marker's uniform scale so it stays a thin vertical line.
    static func updateStem(of entity: Entity, terrainY: Float) {
        guard let stem = entity.findEntity(named: AircraftEntityFactory.stemName) else { return }
        let scale = max(0.001, entity.scale.y)
        let height = max(0.001, entity.position.y - terrainY)
        stem.position = [0, -height / 2 / scale, 0]
        stem.scale = [1, height / scale, 1]
    }
}
