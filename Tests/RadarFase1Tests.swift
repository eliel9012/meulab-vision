import Foundation
import Testing
@testable import MeuLabVision

private struct NoNetworkClient: ADSBProviding {
    func fetch() async throws -> Data { throw CancellationError() }
}

@Suite("Radar Fase 1")
struct RadarFase1Tests {
    @Test func markerStateSelectionWinsOverAging() {
        #expect(RadarMarkerState(selected: true, aging: true) == .selected)
        #expect(RadarMarkerState(selected: false, aging: true) == .aging)
        #expect(RadarMarkerState(selected: false, aging: false) == .normal)
    }

    @Test func gibsCapabilitiesParseOffMain() async {
        let xml = """
        <WMS_Capabilities><Capability><Layer>
          <Layer><Name>Other</Name><Dimension name="time" default="2020-01-01T00:00:00Z"/></Layer>
          <Layer><Name>GOES-East_ABI_Band13_Clean_Infrared</Name>
            <Dimension name="time" default="2026-10-30T12:40:00Z"/></Layer>
        </Layer></Capability></WMS_Capabilities>
        """
        let date = await RadarCloudSnapshot.parseLatestTime(Data(xml.utf8),
                                                            layerName: "GOES-East_ABI_Band13_Clean_Infrared")
        #expect(date == ISO8601DateFormatter().date(from: "2026-10-30T12:40:00Z"))
    }

    @MainActor
    @Test func pollingIsReferenceCounted() {
        let store = FlightStore(client: NoNetworkClient())
        store.acquirePolling("root")
        store.acquirePolling("radar-volume")
        store.releasePolling("radar-volume")
        #expect(store.pollingClients == ["root"])
        store.releasePolling("root")
        #expect(store.pollingClients.isEmpty)
    }

    @MainActor
    @Test func renderableAircraftIsStableForSameSnapshot() {
        let store = FlightStore(client: NoNetworkClient())
        let now = Date()
        let first = store.renderableAircraft(at: now)
        let second = store.renderableAircraft(at: now)
        #expect(first.map(\.hex) == second.map(\.hex))
    }
}
