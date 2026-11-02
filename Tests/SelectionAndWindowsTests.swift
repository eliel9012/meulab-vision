import Foundation
import Testing
@testable import MeuLabVision

private struct FixtureClient: ADSBProviding {
    func fetch() async throws -> Data { Fixture.data("readsb_aircraft") }
}

@Suite("Seleção e janelas")
struct SelectionAndWindowsTests {
    /// Raio largo e idade alta: o fixture é antigo e só importa ter algo renderizável.
    @MainActor private func makeStore() -> FlightStore {
        let store = FlightStore(client: FixtureClient())
        store.settings.maxPositionAgeSeconds = .greatestFiniteMagnitude
        store.settings.minimumAltitudeFeet = -.greatestFiniteMagnitude
        store.settings.radiusKilometers = 20_000
        return store
    }

    @MainActor @Test func deselectingSurvivesTheNextRefresh() async {
        let store = makeStore()
        await store.refresh()
        #expect(store.selectedHex != nil)
        store.selectedHex = nil
        await store.refresh()
        #expect(store.selectedHex == nil)
    }

    @MainActor @Test func vanishedSelectionIsClearedWithoutPickingAnother() async {
        let store = makeStore()
        await store.refresh()
        store.selectedHex = "ffffff"
        await store.refresh()
        #expect(store.selectedHex == nil)
    }

    @MainActor @Test func volumeOpenIsRequestedOncePerPendingOpen() {
        let store = FlightStore(client: FixtureClient())
        let start = Date()
        #expect(store.requestVolumeOpen(now: start))
        #expect(!store.requestVolumeOpen(now: start.addingTimeInterval(1)))
        // A failed open must not block forever.
        #expect(store.requestVolumeOpen(now: start.addingTimeInterval(FlightStore.volumeOpenTimeout + 1)))
    }

    @MainActor @Test func volumeAppearingClearsThePendingRequest() {
        let store = FlightStore(client: FixtureClient())
        let start = Date()
        #expect(store.requestVolumeOpen(now: start))
        store.isVolumeOpen = true
        #expect(!store.requestVolumeOpen(now: start))
        store.isVolumeOpen = false
        #expect(store.requestVolumeOpen(now: start))
    }

    @MainActor @Test func missionControlIsClaimedOncePerPendingOpen() {
        let windows = VisionWindowCoordinator()
        let start = Date()
        #expect(windows.claimMissionControlOpen(now: start))
        #expect(!windows.claimMissionControlOpen(now: start.addingTimeInterval(1)))
        #expect(windows.claimMissionControlOpen(now: start.addingTimeInterval(VisionWindowCoordinator.missionControlClaimTimeout + 1)))
    }

    @MainActor @Test func openOrPushedMissionControlIsNeverClaimed() {
        let windows = VisionWindowCoordinator()
        windows.missionControlAppeared()
        #expect(!windows.claimMissionControlOpen())
        windows.missionControlDisappeared()
        #expect(windows.claimMissionControlOpen())

        let pushed = VisionWindowCoordinator()
        pushed.pushedWindowAppeared()
        #expect(!pushed.claimMissionControlOpen())
    }

    @MainActor @Test func labPollingOutlivesOneWindowClosing() {
        let lab = VisionLabStore()
        lab.acquirePolling("a")
        lab.acquirePolling("b")
        lab.releasePolling("a")
        #expect(lab.pollingClients == ["b"])
        lab.releasePolling("b")
        #expect(lab.pollingClients.isEmpty)
    }

    @MainActor @Test func radioWithoutStreamReportsInsteadOfStayingSilent() {
        let lab = VisionLabStore()
        lab.toggleRadio()
        #expect(!lab.isPlaying)
        #expect(lab.radioError != nil)
    }

    @Test func seededSelectionLosesToExplicitGroupSelection() throws {
        var engine = RadarSyncEngine()
        engine.seedSelection("auto")
        #expect(engine.selection?.value == "auto")
        let snapshot = engine.snapshot()
        #expect(snapshot.count == 1)

        let remote = RadarSyncMessage(stamp: RadarSyncStamp(time: 100, author: UUID()), payload: .selection(hex: "group"))
        #expect(engine.receive(remote) == .applySelection("group"))
        #expect(engine.selection?.value == "group")
    }

    @Test func seedNeverOverridesARealSelection() {
        var engine = RadarSyncEngine()
        _ = engine.localSelection("chosen", now: 100)
        engine.seedSelection("auto")
        #expect(engine.selection?.value == "chosen")
        engine.seedSelection(nil)
        #expect(engine.selection?.value == "chosen")
    }

    @Test func staleLabelAppearsOnlyAfterFifteenMinutes() {
        let now = Date()
        #expect(WidgetContent.ageLabel(updatedAt: now.addingTimeInterval(-14 * 60), now: now) == nil)
        #expect(WidgetContent.ageLabel(updatedAt: now.addingTimeInterval(-20 * 60), now: now) == "há 20 min")
        #expect(WidgetContent.ageLabel(updatedAt: now.addingTimeInterval(-3 * 3_600), now: now) == "há 3 h")
        #expect(WidgetContent.ageLabel(updatedAt: now.addingTimeInterval(60), now: now) == nil)
    }
}
