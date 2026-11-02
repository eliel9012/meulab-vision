import Foundation
import simd
import Testing
@testable import MeuLabVision

struct Fase5PingThrottleTests {
    @Test func firstPingAllowedThenBlockedForTwoSeconds() {
        var throttle = RadarPingThrottle()
        let r1 = throttle.allow(at: 100)
        #expect(r1)
        let r2 = throttle.allow(at: 100.5)
        #expect(!r2)
        let r3 = throttle.allow(at: 101.99)
        #expect(!r3)
        let r4 = throttle.allow(at: 102.0)
        #expect(r4)
        let r5 = throttle.allow(at: 103)
        #expect(!r5)
    }

    @Test func clockGoingBackwardsDoesNotLockForever() {
        var throttle = RadarPingThrottle()
        let r6 = throttle.allow(at: 500)
        #expect(r6)
        let r7 = throttle.allow(at: 10)
        #expect(r7)
        let r8 = throttle.allow(at: 11)
        #expect(!r8)
    }
}

struct Fase5PingPolicyTests {
    @Test func firstSnapshotIsBaselineOnly() {
        var policy = RadarPingPolicy()
        let r9 = policy.event(visibleHexes: [], selectedHex: nil)
        #expect(r9 == nil)
        #expect(!policy.hasBaseline)
        let r10 = policy.event(visibleHexes: ["a", "b"], selectedHex: nil)
        #expect(r10 == nil)
        #expect(policy.hasBaseline)
    }

    @Test func newAircraftPingsOnce() {
        var policy = RadarPingPolicy()
        _ = policy.event(visibleHexes: ["a"], selectedHex: nil)
        let r11 = policy.event(visibleHexes: ["a", "b"], selectedHex: nil)
        #expect(r11 == .appeared("b"))
        let r12 = policy.event(visibleHexes: ["a", "b"], selectedHex: nil)
        #expect(r12 == nil)
        // Leaving and coming back is not "new".
        _ = policy.event(visibleHexes: ["a"], selectedHex: nil)
        let r13 = policy.event(visibleHexes: ["a", "b"], selectedHex: nil)
        #expect(r13 == nil)
    }

    @Test func selectionWinsAndOnlyOnChange() {
        var policy = RadarPingPolicy()
        _ = policy.event(visibleHexes: ["a"], selectedHex: nil)
        let r14 = policy.event(visibleHexes: ["a", "b"], selectedHex: "a")
        #expect(r14 == .selected("a"))
        let r15 = policy.event(visibleHexes: ["a", "b"], selectedHex: "a")
        #expect(r15 == nil)
        let r16 = policy.event(visibleHexes: ["a", "b"], selectedHex: "zzz")
        #expect(r16 == nil)
    }

    @Test func memoryIsBounded() {
        var policy = RadarPingPolicy()
        _ = policy.event(visibleHexes: ["x"], selectedHex: nil)
        let many = (0...RadarPingPolicy.maxRemembered).map { "h\($0)" }
        _ = policy.event(visibleHexes: many, selectedHex: nil)
        _ = policy.event(visibleHexes: ["only"], selectedHex: nil)
        #expect(policy.seen.count <= RadarPingPolicy.maxRemembered + 1)
    }
}

struct Fase5LayoutTests {
    @Test func tableAndRoomScales() {
        let table = ImmersiveRadarLayout.scale(mode: .table)
        #expect(abs(table * RadarVisualGeometry.tableWidth - 0.8) < 0.001)
        let room = ImmersiveRadarLayout.scale(mode: .room, roomWidthMeters: 4)
        #expect(abs(room * RadarVisualGeometry.tableWidth - 4) < 0.001)
        let tooBig = ImmersiveRadarLayout.scale(mode: .room, roomWidthMeters: 20)
        #expect(abs(tooBig * RadarVisualGeometry.tableWidth - 5) < 0.001)
        let tooSmall = ImmersiveRadarLayout.scale(mode: .room, roomWidthMeters: 1)
        #expect(abs(tooSmall * RadarVisualGeometry.tableWidth - 3) < 0.001)
        #expect(ImmersiveRadarLayout.clampRoomWidth(.nan) == ImmersiveRadarLayout.defaultRoomWidthMeters)
    }

    @Test func placementFallsBackToFloatingWithoutTable() {
        #expect(ImmersiveRadarLayout.placement(mode: .table, tableAnchored: false, following: false) == .floating)
        #expect(ImmersiveRadarLayout.placement(mode: .table, tableAnchored: true, following: false) == .table)
        #expect(ImmersiveRadarLayout.placement(mode: .room, tableAnchored: true, following: false) == .room)
        #expect(ImmersiveRadarLayout.placement(mode: .table, tableAnchored: true, following: true) == .following)
    }

    @Test func floatingSitsAboutOneMeterAheadAtTableHeight() {
        let scale = ImmersiveRadarLayout.scale(mode: .table)
        let p = ImmersiveRadarLayout.mountPosition(for: .floating, scale: scale)
        #expect(abs(p.z + 1) < 0.01)
        // Table underside rests on ~0.75 m.
        let underside = p.y - ImmersiveRadarLayout.tableUndersideDepth * scale
        #expect(abs(underside - 0.75) < 0.001)
    }

    @Test func tablePlacementRestsOnAnchorPlane() {
        let scale = ImmersiveRadarLayout.scale(mode: .table)
        let p = ImmersiveRadarLayout.mountPosition(for: .table, scale: scale)
        #expect(p.x == 0 && p.z == 0)
        #expect(abs(p.y - ImmersiveRadarLayout.tableUndersideDepth * scale) < 0.0001)
    }

    @Test func followPutsMarkerOnTarget() {
        let local: SIMD3<Float> = [0.2, 0.1, -0.3]
        let scale: Float = 3
        let mount = ImmersiveRadarLayout.followMountPosition(markerLocal: local, scale: scale)
        let world = mount + local * scale
        #expect(simd_length(world - ImmersiveRadarLayout.followTarget) < 0.0001)
    }

    @Test func smoothingMovesTowardGoalWithoutOvershoot() {
        let start: SIMD3<Float> = .zero
        let goal: SIMD3<Float> = [1, 0, 0]
        let step = ImmersiveRadarLayout.smoothed(start, toward: goal, deltaTime: 1 / 90)
        #expect(step.x > 0 && step.x < 1)
        #expect(ImmersiveRadarLayout.smoothed(start, toward: goal, deltaTime: 0) == start)
        #expect(ImmersiveRadarLayout.smoothed(start, toward: goal, deltaTime: 100).x <= 1)
    }
}

struct Fase5AudioSettingTests {
    @Test func spatialAudioDefaultsOnAndPersists() throws {
        #expect(RadarSettings().spatialAudioEnabled)
        let defaults = try #require(UserDefaults(suiteName: "fase5-\(UUID().uuidString)"))
        #expect(RadarSettingsPersistence.restored(RadarSettings(), from: defaults).spatialAudioEnabled)
        var settings = RadarSettings()
        settings.spatialAudioEnabled = false
        RadarSettingsPersistence.save(settings, to: defaults)
        #expect(!RadarSettingsPersistence.restored(RadarSettings(), from: defaults).spatialAudioEnabled)
    }

    @Test func waveformIsShortBoundedAndSilentAtEdges() {
        for event in [RadarPingEvent.appeared("a"), .selected("a")] {
            let samples = RadarPingWaveform.samples(RadarPingWaveform.tone(for: event))
            #expect(samples.count > 1000 && samples.count < Int(RadarPingWaveform.sampleRate * 0.3))
            #expect(samples.allSatisfy { Swift.abs($0) <= 1 })
            #expect(abs(samples.first ?? 1) < 0.01)
            #expect(abs(samples.last ?? 1) < 0.01)
            let peak = samples.reduce(Float(0)) { max($0, Swift.abs($1)) }
            #expect(peak > 0.1)
        }
    }
}
