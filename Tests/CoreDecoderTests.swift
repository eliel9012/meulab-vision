import Foundation
import Testing
@testable import MeuLabVision

@Suite("Decoders Core")
struct CoreDecoderTests {
    @Test func acarsDashboard() throws {
        let value = try Fixture.decode(ACARSDashboard.self, "acars_summary")
        #expect(value.today.messages == 412)
        #expect(value.today.peakHour == "14:00")
        #expect(value.last24h.peakHour == nil)
        #expect(value.lastHour == 18)
        #expect(value.topAircraft.map(\.id) == ["PR-XBA", "PS-AEA"])
        #expect(value.topLabels.last?.description == nil)
    }

    @Test func acarsHourlyAndHistory() throws {
        let hourly = try Fixture.decode(ACARSHourly.self, "acars_hourly")
        #expect(hourly.hours.map(\.messages) == [30, 44])
        let history = try Fixture.decode(ACARSHistory.self, "acars_history")
        #expect(history.last7Days.count == 2)
        #expect(history.last24hHours.first?.id == "2026-10-30 13:00")
    }

    @Test func acarsMessages() throws {
        let list = try Fixture.decode(ACARSList.self, "acars_messages")
        #expect(list.messages.count == 2)
        let first = list.messages[0]
        #expect(first.labelDesc == "Terminal")
        #expect(first.stationId == "FRANCA")
        #expect(first.altitudeFt == 35000)
        #expect(first.freqMhz == 131.55)
        #expect(first.route == "SBGR → SBRP")
        #expect(list.messages[1].title == "Sem identificação")
        #expect(list.messages[1].route == nil)
        let search = try Fixture.decode(ACARSSearch.self, "acars_messages")
        #expect(search.messages.count == 2)
        let detail = try Fixture.decode(ACARSDetail.self, "acars_detail")
        #expect(detail.message.route == "— → SBRP")
    }

    @Test func alerts() throws {
        let rules = try Fixture.decode([VisionAlertRule].self, "alerts_rules")
        #expect(rules.map(\.enabled) == [true, false])
        #expect(rules[1].lastTriggered == nil)
        let triggers = try Fixture.decode([VisionAlertTrigger].self, "alerts_triggers")
        #expect(triggers.first?.ruleName == "CPU alta")
        #expect(triggers.first?.acknowledged == false)
    }

    @Test func systemAnalytics() throws {
        let value = try Fixture.decode(VisionSystemAnalytics.self, "analytics_system")
        #expect(value.cpu.dataPoints.map(\.usage) == [12.5, 40])
        #expect(value.memory.minimumAvailable == nil)
        #expect(value.disk.dataPoints.isEmpty)
        #expect(value.temperature.minimum == nil)
        #expect(value.uptime?.reboots == 1)
    }

    @Test func adsbAnalytics() throws {
        let value = try Fixture.decode(VisionADSBAnalytics.self, "analytics_adsb")
        #expect(value.totalFlights == 320)
        #expect(value.hourlyStats.last?.flightCount == 31)
        #expect(value.topRoutes == nil)
        #expect(value.topAircraftTypes?.first?.type == "A320")
    }

    @Test func cpuHistory() throws {
        let value = try Fixture.decode(VisionCPUHistory.self, "analytics_system")
        #expect(value.cpu.minimum == 12.5)
        #expect(value.cpu.dataPoints.count == 2)
    }

    @Test func infra() throws {
        let metrics = try Fixture.decode(VisionAPIMetrics.self, "infra_metrics")
        #expect(metrics.cacheHits == 900)
        #expect(metrics.avgResponseMs == 12.4)
        let docker = try Fixture.decode(VisionDockerStatus.self, "docker_status")
        #expect(docker.containers.map(\.names) == ["readsb", "acars"])
        #expect(docker.containers[0].health?.status == "healthy")
        #expect(docker.containers[1].health == nil)
        let systemd = try Fixture.decode(VisionSystemdStatus.self, "systemd_status")
        #expect(systemd.services.first?.subState == "running")
        let disks = try Fixture.decode(VisionDiskHealth.self, "disk_health")
        #expect(disks.ok)
        #expect(disks.devices[0].healthPassed == true)
        #expect(disks.devices[1].model == nil)
    }

    @Test func labStoreModels() throws {
        let processes = try Fixture.decode(VisionProcessList.self, "system_processes")
        #expect(processes.items.map(\.id) == [1, 420])
        #expect(processes.items[1].cpuPercent == 12.5)
        let partitions = try Fixture.decode(VisionPartitionList.self, "system_partitions")
        #expect(partitions.partitions.first?.usedPercent == "42%")
        let network = try Fixture.decode(VisionNetworkStats.self, "system_network")
        #expect(network.interfaces.first?.rxBytes == 9_876_543_210)
        let summary = try Fixture.decode(VisionACARSSummary.self, "lab_acars_summary")
        #expect(summary.lastHour == 18)
        let messages = try Fixture.decode(VisionACARSList.self, "acars_messages")
        #expect(messages.messages.count == 2)
    }

    @Test func openMeteoForecastTruncatesToShortestSeries() throws {
        let value = try Fixture.decode(OpenMeteoForecast.self, "open_meteo_forecast")
        #expect(value.hours.count == 2)
        #expect(value.hours[1].day == "2026-10-30")
        #expect(value.hours[1].hour == "01:00")
        #expect(value.days.map(\.date) == ["2026-10-30", "2026-10-31"])
        #expect(value.days[1].rainChance == 70)
    }

    @Test func decodersThroughMockedClient() async throws {
        let api = MockAPI(routes: [
            "/api/acars/summary": (200, "acars_summary"),
            "/api/system/disk_health": (200, "disk_health")
        ])
        async let summary: ACARSDashboard = api.client.fetch("api/acars/summary")
        async let disks: VisionDiskHealth = api.client.fetch("api/system/disk_health")
        let (s, d) = try await (summary, disks)
        #expect(s.today.flights == 37)
        #expect(d.devices.count == 2)
    }
}
