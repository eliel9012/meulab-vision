import Foundation
import RealityKit
import SwiftUI
import Testing
@testable import MeuLabVision

struct RadarFase2VolumeTests {
    @Test func displayRadiusGrowsWithTableScale() {
        var settings = RadarSettings()
        settings.radiusKilometers = 200
        settings.tableScale = 1.5
        #expect(settings.displayRadiusKilometers == 300)
        #expect(abs(settings.tableWidthMeters - 1.2) < 1e-9)
        #expect(RadarSettings.radiusOptions.contains(300))
        #expect(RadarSettings.tableScaleOptions == [0.25, 0.5, 1.0, 1.25, 1.5, 2.0])
    }

    @Test func smallTableKeepsTheSelectedRange() {
        var settings = RadarSettings()
        settings.radiusKilometers = 100
        settings.tableScale = 0.25
        #expect(settings.displayRadiusKilometers == 100)
        #expect(abs(settings.tableWidthMeters - 0.2) < 1e-9)
        #expect(RadarVolumeSize.drawnSettings(settings).radiusKilometers == 100)
    }

    @Test func drawnSettingsCarryDisplayRadiusOnce() {
        var settings = RadarSettings()
        settings.radiusKilometers = 100
        settings.tableScale = 2
        let drawn = RadarVolumeSize.drawnSettings(settings)
        #expect(drawn.radiusKilometers == 200)
        #expect(drawn.displayRadiusKilometers == 200)
    }

    @Test func volumeSizeScalesWithTable() {
        let size = RadarVolumeSize.meters(tableScale: 2)
        #expect(abs(size.width - 3.2 * 2 / 3) < 1e-9)
        #expect(abs(size.height - 1.6) < 1e-9)
        #expect(abs(size.depth - 2.8 * 2 / 3) < 1e-9)
    }

    @Test func mountScaleMakesTheTableItsPhysicalWidth() {
        for scale in RadarSettings.tableScaleOptions {
            var settings = RadarSettings()
            settings.tableScale = scale
            let meters = RadarVolumeSize.mountScale(tableScale: scale) * RadarVisualGeometry.tableWidth
            #expect(abs(Double(meters) - settings.tableWidthMeters) < 1e-5)
        }
    }

    @Test func yawOnlyDropsTiltAndKeepsHeading() {
        let yaw = simd_quatf(angle: 0.7, axis: [0, 1, 0])
        let tilt = simd_quatf(angle: 0.3, axis: [1, 0, 0])
        let result = RadarTableManipulation.yawOnly(yaw * tilt)
        let up = result.act([0, 1, 0])
        #expect(abs(up.y - 1) < 1e-4)
        let pure = RadarTableManipulation.yawOnly(yaw)
        #expect(abs(abs(simd_dot(pure.vector, yaw.vector)) - 1) < 1e-4)
    }

    @Test func yawOnlyHandlesVerticalForward() {
        let pitch = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        let result = RadarTableManipulation.yawOnly(pitch)
        #expect(abs(result.act([0, 1, 0]).y - 1) < 1e-4)
    }

    @Test func scaleIsUniformAndClamped() {
        #expect(RadarTableManipulation.clampScale([5, 5, 5]) == SIMD3(repeating: 1.25))
        #expect(RadarTableManipulation.clampScale([0.1, 0.1, 0.1]) == SIMD3(repeating: 0.6))
        #expect(RadarTableManipulation.clampScale([0.9, 1.0, 1.1]) == SIMD3(repeating: 1.0))
    }

    @MainActor
    @Test func tapResolvesHexThroughParents() {
        let marker = Entity()
        marker.name = "flight:abc123"
        let child = Entity()
        let grandchild = Entity()
        marker.addChild(child)
        child.addChild(grandchild)
        #expect(RadarEntityHit.hex(for: grandchild) == "abc123")
        #expect(RadarEntityHit.hex(for: marker) == "abc123")
        #expect(RadarEntityHit.hex(for: Entity()) == nil)
    }

    @Test func ornamentFollowsViewpoint() {
        #expect(RadarViewpointLayout.ornamentAnchor(for: .front) == .bottomFront)
        #expect(RadarViewpointLayout.ornamentAnchor(for: .back) == .bottomBack)
        #expect(RadarViewpointLayout.ornamentAnchor(for: .left) == .bottomLeading)
        #expect(RadarViewpointLayout.ornamentAnchor(for: .right) == .bottomTrailing)
    }

    @Test func persistenceRoundTripsAndRejectsUnknownValues() throws {
        let suite = "radar-fase2-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(RadarSettingsPersistence.restored(RadarSettings(), from: defaults) == RadarSettings())

        var settings = RadarSettings()
        settings.radiusKilometers = 300
        settings.tableScale = 1.25
        RadarSettingsPersistence.save(settings, to: defaults)
        let restored = RadarSettingsPersistence.restored(RadarSettings(), from: defaults)
        #expect(restored.radiusKilometers == 300)
        #expect(restored.tableScale == 1.25)

        defaults.set(123.0, forKey: RadarSettingsPersistence.radiusKey)
        defaults.set(7.0, forKey: RadarSettingsPersistence.tableScaleKey)
        let fallback = RadarSettingsPersistence.restored(RadarSettings(), from: defaults)
        #expect(fallback.radiusKilometers == RadarSettings().radiusKilometers)
        #expect(fallback.tableScale == 1)
    }
}
