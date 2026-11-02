import Foundation
import Testing
@testable import MeuLabVision

@Suite("Fase 4 · deep link")
struct Fase4DeepLinkTests {
    @Test(arguments: VisionSection.allCases)
    func urlRoundTrip(section: VisionSection) {
        let url = VisionDeepLink.url(for: section)
        #expect(url.scheme == "meulabvision")
        #expect(VisionDeepLink.section(from: url) == section)
    }

    @Test func parsesCanonicalURLs() throws {
        let cases: [(String, VisionSection)] = [
            ("meulabvision://section/radar", .radar),
            ("meulabvision://section/system", .system),
            ("meulabvision://section/alerts", .alerts),
            ("meulabvision://section/trip", .trip),
            ("MeuLabVision://Section/ALERTS", .alerts),
            ("meulabvision://section/weather/", .weather),
            ("meulabvision://acars", .acars),
        ]
        for (string, expected) in cases {
            let url = try #require(URL(string: string))
            #expect(VisionDeepLink.section(from: url) == expected, "\(string)")
        }
    }

    @Test func rejectsInvalidURLs() throws {
        for string in [
            "https://section/radar",
            "meulabvision://section",
            "meulabvision://section/",
            "meulabvision://section/ADS-B",
            "meulabvision://section/unknown",
            "meulabvision://other/radar",
            "meulabvision:radar",
        ] {
            let url = try #require(URL(string: string))
            #expect(VisionDeepLink.section(from: url) == nil, "\(string)")
        }
    }

    @Test func canonicalURLFormat() {
        #expect(VisionDeepLink.url(for: .system).absoluteString == "meulabvision://section/system")
        #expect(VisionDeepLink.url(for: .radar).absoluteString == "meulabvision://section/radar")
    }

    @MainActor
    @Test func routerHandlesAndConsumes() throws {
        let router = VisionDeepLinkRouter()
        #expect(router.handle(try #require(URL(string: "meulabvision://section/alerts"))))
        let request = try #require(router.pending)
        #expect(request.section == .alerts)
        #expect(!router.handle(try #require(URL(string: "meulabvision://section/nope"))))
        #expect(router.pending == request)

        router.open(.alerts)
        let newer = try #require(router.pending)
        #expect(newer != request) // mesmo destino, pedido distinto
        router.consume(request)   // pedido antigo não limpa o novo
        #expect(router.pending == newer)
        router.consume(newer)
        #expect(router.pending == nil)
    }
}

@Suite("Fase 4 · AppEnum")
struct Fase4AppEnumTests {
    @Test(arguments: VisionSection.allCases)
    func sectionRoundTrip(section: VisionSection) {
        #expect(SectionAppEnum(section).section == section)
        #expect(VisionSection(routeID: section.routeID) == section)
    }

    @Test func casesMatchOneToOne() {
        #expect(SectionAppEnum.allCases.count == VisionSection.allCases.count)
        #expect(Set(SectionAppEnum.allCases.map(\.section)) == Set(VisionSection.allCases))
        #expect(Set(SectionAppEnum.caseDisplayRepresentations.keys) == Set(SectionAppEnum.allCases))
    }

    @Test func routeIDsAreCaseNames() {
        #expect(VisionSection.radar.routeID == "radar")
        #expect(VisionSection.system.routeID == "system")
        #expect(VisionSection.alerts.routeID == "alerts")
        #expect(VisionSection.infrastructure.routeID == "infrastructure")
        #expect(VisionSection(routeID: "Viagem") == nil) // rawValue em português não é id
    }

    @MainActor
    @Test func openIntentRoutesToSection() async throws {
        let intent = OpenSectionIntent(target: .weather)
        _ = try await intent.perform()
        let request = try #require(VisionDeepLinkRouter.shared.pending)
        #expect(request.section == .weather)
        VisionDeepLinkRouter.shared.consume(request)
    }

    @Test func dialogs() {
        #expect(VisionIntentDialogs.aircraft(0) == "Nenhuma aeronave no radar agora.")
        #expect(VisionIntentDialogs.aircraft(1) == "O radar está rastreando 1 aeronave.")
        #expect(VisionIntentDialogs.aircraft(12) == "O radar está rastreando 12 aeronaves.")
        #expect(VisionIntentDialogs.alerts([]) == "Nenhum alerta pendente no MeuLab.")
        #expect(VisionIntentDialogs.alerts([trigger("1", rule: "CPU")]) == "1 alerta pendente: CPU.")
        let many = (1...4).map { trigger("\($0)", rule: "R\($0)") }
        #expect(VisionIntentDialogs.alerts(many) == "4 alertas pendentes. Mais recentes: R1, R2, R3.")
    }
}

@Suite("Fase 4 · notificações de alerta")
struct Fase4NotificationTests {
    @Test func firstLoadOnlySeeds() {
        var ledger = AlertNotificationLedger()
        let fresh = ledger.ingest([trigger("a"), trigger("b")], notify: false)
        #expect(fresh.isEmpty)
        #expect(ledger.knownIDs == ["a", "b"])
    }

    @Test func notifiesOnlyNewUnacknowledgedDeltas() {
        var ledger = AlertNotificationLedger()
        _ = ledger.ingest([trigger("a"), trigger("b")], notify: false)
        let fresh = ledger.ingest([trigger("c"), trigger("d", acknowledged: true), trigger("a"), trigger("b")],
                                  notify: true)
        #expect(fresh.map(\.id) == ["c"])
        #expect(ledger.ingest([trigger("c"), trigger("a")], notify: true).isEmpty) // dedup
        #expect(ledger.contains("d"))
    }

    @Test func duplicateIDsInSameBatchNotifyOnce() {
        var ledger = AlertNotificationLedger()
        let fresh = ledger.ingest([trigger("x"), trigger("x")], notify: true)
        #expect(fresh.map(\.id) == ["x"])
        #expect(ledger.knownIDs == ["x"])
    }

    @Test func capacityKeepsMostRecent() {
        var ledger = AlertNotificationLedger()
        let total = AlertNotificationLedger.capacity + 10
        _ = ledger.ingest((0..<total).map { trigger("t\($0)") }, notify: false)
        #expect(ledger.knownIDs.count == AlertNotificationLedger.capacity)
        #expect(!ledger.contains("t0"))
        #expect(ledger.contains("t\(total - 1)"))
    }

    @Test func persistsAcrossLaunches() throws {
        let suite = "fase4.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        var ledger = AlertNotificationLedger.load(from: defaults)
        _ = ledger.ingest([trigger("a"), trigger("b")], notify: false)
        ledger.save(to: defaults)

        var reloaded = AlertNotificationLedger.load(from: defaults)
        #expect(reloaded == ledger)
        let fresh = reloaded.ingest([trigger("a"), trigger("b"), trigger("c")], notify: true)
        #expect(fresh.map(\.id) == ["c"])
    }

    @Test func resolvesActions() {
        #expect(AlertNotificationAction.resolve(actionIdentifier: AlertNotificationAction.acknowledgeActionID,
                                                alertID: "42") == .acknowledge("42"))
        #expect(AlertNotificationAction.resolve(actionIdentifier: AlertNotificationAction.acknowledgeActionID,
                                                alertID: nil) == .openAlerts)
        #expect(AlertNotificationAction.resolve(actionIdentifier: AlertNotificationAction.defaultActionID,
                                                alertID: "42") == .openAlerts)
        #expect(AlertNotificationAction.resolve(actionIdentifier: "com.apple.UNNotificationDismissActionIdentifier",
                                                alertID: "42") == .ignore)
        #expect(AlertNotificationAction.requestID(for: "42") == "alert-42")
    }
}

private func trigger(_ id: String, rule: String = "Regra", acknowledged: Bool = false) -> VisionAlertTrigger {
    VisionAlertTrigger(id: id, ruleName: rule, triggeredAt: "2026-10-30T12:00:00Z",
                       value: 90, threshold: 80, message: "msg \(id)", acknowledged: acknowledged)
}
