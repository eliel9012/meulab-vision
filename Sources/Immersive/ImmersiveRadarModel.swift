import Foundation
import simd

/// How the radar is laid out inside the immersive space.
enum ImmersiveRadarMode: String, CaseIterable, Identifiable, Sendable {
    /// Radar on a real table (plane anchor), floating at table height when none is found.
    case table = "Mesa"
    /// Room-scale radar (3–5 m) on the floor around the user.
    case room = "Sala"

    var id: String { rawValue }
}

/// Where the radar mount actually sits right now.
enum ImmersiveRadarPlacement: Equatable, Sendable {
    /// Parented to the detected horizontal `.table` plane.
    case table
    /// No table yet (or plane tracking unavailable): floats ~1 m ahead at table height.
    case floating
    /// Room scale, on the floor.
    case room
    /// Follow mode: selected aircraft held in front of the user.
    case following
}

/// Pure layout math for the immersive radar (testable, no RealityKit).
///
/// Coordinates are immersive-space coordinates: origin on the floor under the user at
/// launch, -Z forward, +Y up. True north is NOT known: visionOS gives apps no compass /
/// heading (`CLLocationManager.headingAvailable` is false on Vision Pro and ARKit's
/// `WorldTrackingProvider` world frame is gravity-aligned with an arbitrary yaw). The red
/// north marker therefore points "forward" at launch and the user can rotate the radar
/// (yaw-only manipulation) to align it with the real north.
enum ImmersiveRadarLayout {
    /// Physical width of the radar in table mode (fits a typical 0.6–1 m table).
    static let tableWidthMeters: Double = 0.8
    /// Allowed room-scale widths.
    static let roomWidthRange: ClosedRange<Double> = 3...5
    static let defaultRoomWidthMeters: Double = 4
    /// Fallback spot when no table is detected: ~1 m ahead, typical table height.
    static let floatingPosition: SIMD3<Float> = [0, 0.75, -1.0]
    /// Room mode centre: slightly ahead, so the user stands inside the map.
    static let roomCenter: SIMD3<Float> = [0, 0, -0.6]
    /// Room mode keeps the table top a little above the floor.
    static let roomFloorClearance: Float = 0.03
    /// Follow mode keeps the selected aircraft here (eye level, arm's length).
    static let followTarget: SIMD3<Float> = [0, 1.35, -0.9]
    /// Distance from `RadarSceneController.root` origin to the underside of its table.
    static var tableUndersideDepth: Float { -RadarVisualGeometry.groundY + 0.024 }

    /// Uniform scale applied to the radar mount (scene units: 1.2 m base table).
    static func scale(mode: ImmersiveRadarMode, roomWidthMeters: Double = defaultRoomWidthMeters) -> Float {
        let base = Double(RadarVisualGeometry.tableWidth)
        switch mode {
        case .table: return Float(tableWidthMeters / base)
        case .room: return Float(clampRoomWidth(roomWidthMeters) / base)
        }
    }

    static func clampRoomWidth(_ meters: Double) -> Double {
        guard meters.isFinite else { return defaultRoomWidthMeters }
        return min(roomWidthRange.upperBound, max(roomWidthRange.lowerBound, meters))
    }

    /// Placement for the current mode and table detection state.
    static func placement(mode: ImmersiveRadarMode, tableAnchored: Bool, following: Bool) -> ImmersiveRadarPlacement {
        if following { return .following }
        switch mode {
        case .room: return .room
        case .table: return tableAnchored ? .table : .floating
        }
    }

    /// Mount position relative to its parent (anchor or world) so the radar's table
    /// underside rests on the surface / floor / floating point.
    static func mountPosition(for placement: ImmersiveRadarPlacement, scale: Float) -> SIMD3<Float> {
        let lift = tableUndersideDepth * scale
        switch placement {
        case .table: return [0, lift, 0]
        case .floating: return floatingPosition + [0, lift, 0]
        case .room: return roomCenter + [0, lift + roomFloorClearance, 0]
        case .following: return followTarget
        }
    }

    /// Follow mode: mount position that puts a marker (in mount-local coordinates)
    /// exactly on `target`. The mount carries only a uniform scale and a yaw rotation.
    static func followMountPosition(markerLocal: SIMD3<Float>, scale: Float,
                                    rotation: simd_quatf = simd_quatf(angle: 0, axis: [0, 1, 0]),
                                    target: SIMD3<Float> = followTarget) -> SIMD3<Float> {
        target - rotation.act(markerLocal * scale)
    }

    /// Frame-rate independent smoothing toward a goal (exponential, `rate` per second).
    static func smoothed(_ current: SIMD3<Float>, toward goal: SIMD3<Float>, deltaTime: Float, rate: Float = 4) -> SIMD3<Float> {
        guard deltaTime.isFinite, deltaTime > 0 else { return current }
        let t = 1 - exp(-rate * deltaTime)
        return current + (goal - current) * min(1, max(0, t))
    }
}

/// What deserves a ping.
enum RadarPingEvent: Equatable, Sendable {
    case selected(String)
    case appeared(String)

    var hex: String {
        switch self {
        case let .selected(hex), let .appeared(hex): hex
        }
    }
}

/// Detects newly appeared aircraft and selection changes. The first non-empty snapshot
/// only builds the baseline (no ping storm on launch / scene open).
struct RadarPingPolicy: Sendable {
    private(set) var hasBaseline = false
    private(set) var lastSelectedHex: String?
    private(set) var seen: Set<String> = []
    /// Bound on remembered hexes; on overflow the memory restarts from the visible set.
    static let maxRemembered = 4_000

    mutating func event(visibleHexes: [String], selectedHex: String?) -> RadarPingEvent? {
        let visible = Set(visibleHexes)
        guard hasBaseline else {
            guard !visible.isEmpty else { return nil }
            hasBaseline = true
            seen = visible
            lastSelectedHex = selectedHex
            return nil
        }
        defer {
            if seen.count > Self.maxRemembered { seen = visible } else { seen.formUnion(visible) }
        }
        let previousSelection = lastSelectedHex
        lastSelectedHex = selectedHex
        if let selectedHex, selectedHex != previousSelection, visible.contains(selectedHex) {
            return .selected(selectedHex)
        }
        // Stable order so tests (and repeated runs) are deterministic.
        if let fresh = visibleHexes.first(where: { !seen.contains($0) }) {
            return .appeared(fresh)
        }
        return nil
    }
}

/// At most one ping every `interval` seconds, shared by every radar scene.
struct RadarPingThrottle: Sendable {
    var interval: TimeInterval = 2
    private(set) var lastFire: TimeInterval?

    init(interval: TimeInterval = 2) { self.interval = interval }

    mutating func allow(at now: TimeInterval) -> Bool {
        if let lastFire, now - lastFire < interval, now >= lastFire { return false }
        lastFire = now
        return true
    }
}

/// Procedural ping waveform (mono Float32 samples): short sine chirp with a fast
/// attack and exponential decay. Pure so it can be tested without audio hardware.
enum RadarPingWaveform {
    static let sampleRate: Double = 48_000

    struct Tone: Equatable, Sendable {
        var startFrequency: Double
        var endFrequency: Double
        var duration: Double
        var amplitude: Float
    }

    /// New aircraft: bright, rising blip. Selected: lower, falling "lock-on" tone.
    static func tone(for event: RadarPingEvent) -> Tone {
        switch event {
        case .appeared: Tone(startFrequency: 1_250, endFrequency: 1_650, duration: 0.16, amplitude: 0.5)
        case .selected: Tone(startFrequency: 990, endFrequency: 740, duration: 0.24, amplitude: 0.6)
        }
    }

    static func samples(_ tone: Tone, sampleRate: Double = sampleRate) -> [Float] {
        let count = max(1, Int(tone.duration * sampleRate))
        let attack = max(1, Int(0.005 * sampleRate))
        var phase = 0.0
        var output = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let progress = Double(i) / Double(count)
            let frequency = tone.startFrequency + (tone.endFrequency - tone.startFrequency) * progress
            phase += 2 * .pi * frequency / sampleRate
            let envelope = (i < attack ? Double(i) / Double(attack) : 1) * exp(-5 * progress)
            // Fade the last 2 ms so the buffer never ends with a click.
            let tail = min(1, Double(count - i) / (0.002 * sampleRate))
            output[i] = Float(sin(phase) * envelope * tail) * tone.amplitude
        }
        return output
    }
}
