import Foundation
import Testing
@testable import MeuLabVision

private func trigger(id: String = "t1", rule: String = "CPU alta", at: String = "2026-10-30T12:00:00Z",
                     value: Double = 95, threshold: Double = 80, message: String = "CPU 95%",
                     acknowledged: Bool = false) -> VisionAlertTrigger {
    VisionAlertTrigger(id: id, ruleName: rule, triggeredAt: at, value: value, threshold: threshold,
                       message: message, acknowledged: acknowledged)
}

@Suite("Fase 6 · AlertEntity")
struct Fase6AlertEntityTests {
    @Test func mapsTriggerToEntity() throws {
        let entity = AlertEntity(trigger: trigger(), host: "radar")
        #expect(entity.id == "t1")
        #expect(entity.title == "CPU alta")
        #expect(entity.host == "radar")
        #expect(entity.severity == .critical)
        #expect(!entity.acknowledged)
        let date = try #require(entity.date)
        #expect(date == Date(timeIntervalSince1970: 1_793_361_600))
        #expect(entity.subtitle == "Crítico · radar · CPU 95%")
        #expect(entity.deepLink.absoluteString == "meulabvision://alert/t1")
        #expect(!entity.hideInSpotlight)
    }

    @Test func fallbackHostAndAcknowledged() {
        let entity = AlertEntity(trigger: trigger(at: "lixo", acknowledged: true), host: "  ")
        #expect(entity.host == AlertEntity.fallbackHost)
        #expect(entity.date == nil)
        #expect(entity.hideInSpotlight)
        #expect(entity.subtitle.hasSuffix("· reconhecido"))
    }

    @Test(arguments: [
        (50.0, 80.0, AlertSeverity.info),
        (80.0, 80.0, .warning),
        (87.9, 80.0, .warning),
        (88.0, 80.0, .critical),
        (5.0, 0.0, .warning),
    ])
    func severity(value: Double, threshold: Double, expected: AlertSeverity) {
        #expect(AlertSeverity(value: value, threshold: threshold) == expected)
    }

    @Test func suggestionOrderAndMatching() {
        let entities = AlertEntityMapper.entities(from: [
            trigger(id: "ack", value: 99, acknowledged: true),
            trigger(id: "warn", rule: "Disco", value: 81, message: "Disco 81%"),
            trigger(id: "crit-old", at: "2026-10-29T12:00:00Z"),
            trigger(id: "crit-new"),
        ], host: "radar")
        #expect(AlertEntityMapper.sortedForSuggestion(entities).map(\.id) == ["crit-new", "crit-old", "warn", "ack"])
        #expect(AlertEntityMapper.matching("disco", in: entities).map(\.id) == ["warn"])
        #expect(AlertEntityMapper.matching("crítico", in: entities).count == 3)
        #expect(AlertEntityMapper.matching(" ", in: entities).count == 4)
    }
}

@Suite("Fase 6 · deep link de alerta")
struct Fase6AlertDeepLinkTests {
    @Test(arguments: ["t1", "t/1", "alerta com espaço", "ação#2"])
    func roundTrip(id: String) {
        let url = VisionDeepLink.url(forAlert: id)
        #expect(url.scheme == "meulabvision")
        #expect(VisionDeepLink.alertID(from: url) == id)
        #expect(VisionDeepLink.section(from: url) == .alerts)
    }

    @Test func rejectsAlertURLWithoutID() throws {
        let url = try #require(URL(string: "meulabvision://alert/"))
        #expect(VisionDeepLink.alertID(from: url) == nil)
        #expect(VisionDeepLink.alertID(from: VisionDeepLink.url(for: .alerts)) == nil)
    }

    @MainActor
    @Test func routerOpensAlert() throws {
        let router = VisionDeepLinkRouter()
        #expect(router.handle(VisionDeepLink.url(forAlert: "t/1")))
        #expect(router.pending?.section == .alerts)
        #expect(router.focusedAlertID == "t/1")
        #expect(router.consumeFocusedAlert() == "t/1")
        #expect(router.focusedAlertID == nil)

        router.openAlert(id: "x")
        #expect(router.focusedAlertID == "x")
        #expect(router.pending?.section == .alerts)
    }
}

@Suite("Fase 6 · scan do homelab")
struct Fase6ScanSummaryTests {
    private func system(host: String = "radar", cpu: Double = 23.4, temp: Double = 52.2) throws -> SystemStatus {
        let json = """
        {"timestamp":"2026-10-30T12:00:00Z","hostname":"\(host)","location":"casa",
         "cpu":{"usage_percent":\(cpu),"temperature_c":\(temp)}}
        """
        return try JSONDecoder().decode(SystemStatus.self, from: Data(json.utf8))
    }

    @Test func summarizesFixtures() throws {
        let summary = HomelabScanner.summarize(
            system: try system(),
            docker: try Fixture.decode(VisionDockerStatus.self, "docker_status"),
            systemd: try Fixture.decode(VisionSystemdStatus.self, "systemd_status"),
            triggers: [trigger(), trigger(id: "w", value: 81), trigger(id: "a", acknowledged: true)])
        #expect(summary.containersTotal == 2)
        #expect(summary.containersRunning == 1)
        #expect(summary.unhealthyContainers == ["acars"])
        #expect(summary.failedServices.isEmpty)
        #expect(summary.pendingAlerts == 2)
        #expect(summary.criticalAlerts == 1)
        #expect(summary.failedSources.isEmpty)
        #expect(summary.hasProblems)
        #expect(summary.text == "radar: CPU 23%, 52°C. Docker 1/2 rodando (1 com problema: acars). Systemd ok. 2 alertas pendentes (1 crítico).")
    }

    @Test func allSourcesFailed() {
        let summary = HomelabScanner.summarize(system: nil, docker: nil, systemd: nil, triggers: nil)
        #expect(!summary.hasProblems)
        #expect(summary.text == "MeuLab: sistema sem dados. Sem resposta de: sistema, Docker, systemd, alertas.")
    }

    @Test func formatsFailedServicesAndSingleAlert() {
        var summary = HomelabScanSummary()
        summary.hostname = "pi"
        summary.cpuPercent = 9.6
        summary.failedServices = ["a", "b", "c", "d", "e"]
        summary.pendingAlerts = 1
        summary.criticalAlerts = 1
        #expect(summary.text == "pi: CPU 10%. Systemd: 5 com falha (a, b, c e mais 2). 1 alerta pendente (crítico).")

        summary.failedServices = []
        summary.pendingAlerts = 0
        #expect(summary.text == "pi: CPU 10%. Systemd ok. Nenhum alerta pendente.")
    }

    @Test func statusSummaryFallsBackToSnapshot() {
        let snapshot = WidgetSnapshot(
            system: .init(hostname: "radar", cpuPercent: 40, memoryPercent: nil, diskPercent: nil, temperatureC: 60),
            alerts: .init(pendingCount: 3, latestMessage: nil),
            radar: .init(aircraftCount: 12, positionedCount: 10),
            updatedAt: .now)
        let live = LabStatusSummary(hostname: nil, cpuPercent: 10, temperatureC: nil, aircraftCount: nil, pendingAlerts: 0)
        let filled = live.filled(from: snapshot)
        #expect(filled == LabStatusSummary(hostname: "radar", cpuPercent: 10, temperatureC: 60, aircraftCount: 12, pendingAlerts: 0,
                                           staleSince: snapshot.updatedAt))
        #expect(filled.cpuText == "10%")
        #expect(filled.title == "MeuLab · radar")
        #expect(LabStatusSummary().aircraftText == "—")
    }

    @Test func statusSummaryOnlyStaleWhenSnapshotWasUsed() {
        let snapshot = WidgetSnapshot(
            system: .init(hostname: "radar", cpuPercent: 40, memoryPercent: nil, diskPercent: nil, temperatureC: 60),
            alerts: .init(pendingCount: 3, latestMessage: nil),
            radar: .init(aircraftCount: 12, positionedCount: 10),
            updatedAt: .now)
        let live = LabStatusSummary(hostname: "pi", cpuPercent: 10, temperatureC: 50, aircraftCount: 1, pendingAlerts: 0)
        #expect(live.filled(from: snapshot).staleSince == nil)
        #expect(LabStatusSummary(hostname: "pi").filled(from: snapshot).staleSince == snapshot.updatedAt)
    }

    @Test func unknownAlertStillResolvesWithoutTouchingKnownOnes() {
        let known = AlertEntity(id: "a", title: "CPU", message: "alta", severity: .critical,
                                host: "radar", date: nil, acknowledged: false)
        let resolved = AlertEntityMapper.resolving(["a", "antigo"], in: [known])
        #expect(resolved.map(\.id) == ["a", "antigo"])
        #expect(resolved[0] == known)
        #expect(resolved[1].title == "Alerta do MeuLab")
    }
}
