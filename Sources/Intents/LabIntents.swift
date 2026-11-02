import AppIntents
import Foundation
import SwiftUI

// MARK: - Abrir alerta

/// Abre o app na seção Alertas focando o alerta escolhido (Spotlight, Siri, Shortcuts).
struct OpenAlertIntent: OpenIntent, TargetContentProvidingIntent {
    static let title: LocalizedStringResource = "Abrir alerta do MeuLab"
    static let description = IntentDescription("Abre o MeuLab Vision na seção Alertas, no alerta escolhido.")
    static let supportedModes: IntentModes = .foreground(.immediate)

    @Parameter(title: "Alerta")
    var target: AlertEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Abrir \(\.$target)")
    }

    init() {}

    init(target: AlertEntity) {
        self.target = target
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        VisionDeepLinkRouter.shared.openAlert(id: target.id)
        return .result()
    }
}

// MARK: - Status (snippet)

/// Números mostrados no snippet de status. Campos `nil` = fonte indisponível.
struct LabStatusSummary: Equatable, Sendable {
    var hostname: String?
    var cpuPercent: Double?
    var temperatureC: Double?
    var aircraftCount: Int?
    var pendingAlerts: Int?
    /// Data do snapshot quando algum número veio dele em vez da API.
    var staleSince: Date?

    var cpuText: String { cpuPercent.map { "\(Int($0.rounded()))%" } ?? "—" }
    var temperatureText: String { temperatureC.map { "\(Int($0.rounded()))°C" } ?? "—" }
    var aircraftText: String { aircraftCount.map(String.init) ?? "—" }
    var alertsText: String { pendingAlerts.map(String.init) ?? "—" }
    var title: String { hostname.map { "MeuLab · \($0)" } ?? "MeuLab" }

    /// Completa o que faltou com o último snapshot dos widgets.
    func filled(from snapshot: WidgetSnapshot?) -> LabStatusSummary {
        guard let snapshot else { return self }
        var copy = self
        copy.hostname = hostname ?? snapshot.system?.hostname
        copy.cpuPercent = cpuPercent ?? snapshot.system?.cpuPercent
        copy.temperatureC = temperatureC ?? snapshot.system?.temperatureC
        copy.aircraftCount = aircraftCount ?? snapshot.radar?.aircraftCount
        copy.pendingAlerts = pendingAlerts ?? snapshot.alerts?.pendingCount
        if copy != self { copy.staleSince = snapshot.updatedAt }
        return copy
    }
}

enum LabStatusLoader {
    static func load() async -> LabStatusSummary {
        async let status: SystemStatus? = try? await VisionAPIClient.shared.fetch("api/system/status")
        async let triggers: [VisionAlertTrigger]? = try? VisionAlertsAPI.fetchTriggers()
        async let aircraft: Int? = aircraftCount()
        let system = await status
        let pending = await triggers?.filter { !$0.acknowledged }.count
        let summary = LabStatusSummary(hostname: system?.hostname,
                                       cpuPercent: system?.cpu?.usagePercent,
                                       temperatureC: system?.cpu?.temperatureC,
                                       aircraftCount: await aircraft,
                                       pendingAlerts: pending)
        return summary.filled(from: WidgetSnapshot.load())
    }

    private static func aircraftCount() async -> Int? {
        guard let data = try? await ADSBClient().fetch() else { return nil }
        return try? AircraftDecoder.decode(data).aircraft.count
    }
}

/// Snippet interativo com CPU, temperatura, aviões e alertas. Recarregável
/// com `LabStatusSnippetIntent.reload()`.
struct LabStatusSnippetIntent: SnippetIntent {
    static let title: LocalizedStringResource = "Painel de status do MeuLab"
    static let isDiscoverable = false
    static let allowedExecutionTargets: IntentExecutionTargets = [.main]

    init() {}

    func perform() async throws -> some IntentResult & ShowsSnippetView {
        let summary = await LabStatusLoader.load()
        return .result(view: LabStatusSnippetView(summary: summary))
    }
}

/// "Status do MeuLab": mostra o snippet sem abrir o app.
struct LabStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Status do MeuLab"
    static let description = IntentDescription("Mostra CPU, temperatura, aeronaves e alertas pendentes do MeuLab num painel.")
    static let supportedModes: IntentModes = .background
    static let allowedExecutionTargets: IntentExecutionTargets = [.main]

    init() {}

    func perform() async throws -> some IntentResult & ShowsSnippetIntent {
        .result(snippetIntent: LabStatusSnippetIntent())
    }
}

struct LabStatusSnippetView: View {
    let summary: LabStatusSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(summary.title, systemImage: "server.rack")
                .font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                GridRow {
                    metric("CPU", summary.cpuText, symbol: "cpu")
                    metric("Temperatura", summary.temperatureText, symbol: "thermometer.medium")
                }
                GridRow {
                    metric("Aeronaves", summary.aircraftText, symbol: "airplane")
                    metric("Alertas", summary.alertsText, symbol: "bell.badge",
                           tint: (summary.pendingAlerts ?? 0) > 0 ? .orange : .secondary)
                }
            }
            if let staleSince = summary.staleSince {
                Text("Sem resposta da API: parte dos dados é de \(staleSince, style: .relative) atrás")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    private func metric(_ title: String, _ value: String, symbol: String,
                        tint: Color = .secondary) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.title3.monospacedDigit().weight(.semibold))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Scan do homelab (long-running)

/// Resultado do scan: sistema + infraestrutura + alertas. `nil` = fonte falhou.
struct HomelabScanSummary: Equatable, Sendable {
    var hostname: String?
    var cpuPercent: Double?
    var temperatureC: Double?
    var containersRunning: Int?
    var containersTotal: Int?
    var unhealthyContainers: [String] = []
    var failedServices: [String] = []
    var pendingAlerts: Int?
    var criticalAlerts: Int = 0
    var failedSources: [String] = []

    var hasProblems: Bool {
        !unhealthyContainers.isEmpty || !failedServices.isEmpty || (pendingAlerts ?? 0) > 0
    }

    /// Resumo falado/mostrado. Ex.: "radar: CPU 23%, 52°C. Docker 9/10 rodando
    /// (1 com problema: grafana). Systemd ok. 2 alertas pendentes (1 crítico)."
    var text: String {
        var sentences: [String] = []

        var system: [String] = []
        if let cpuPercent { system.append("CPU \(Int(cpuPercent.rounded()))%") }
        if let temperatureC { system.append("\(Int(temperatureC.rounded()))°C") }
        let host = hostname ?? "MeuLab"
        sentences.append(system.isEmpty ? "\(host): sistema sem dados" : "\(host): " + system.joined(separator: ", "))

        if let containersTotal, let containersRunning {
            var docker = "Docker \(containersRunning)/\(containersTotal) rodando"
            if !unhealthyContainers.isEmpty {
                docker += " (\(Self.problemList(unhealthyContainers)))"
            }
            sentences.append(docker)
        }

        if !failedServices.isEmpty {
            sentences.append("Systemd: \(failedServices.count) com falha (\(Self.names(failedServices)))")
        } else if !failedSources.contains(HomelabScanner.Source.systemd.label) {
            sentences.append("Systemd ok")
        }

        if let pendingAlerts {
            switch pendingAlerts {
            case 0: sentences.append("Nenhum alerta pendente")
            case 1: sentences.append("1 alerta pendente" + (criticalAlerts > 0 ? " (crítico)" : ""))
            default:
                sentences.append("\(pendingAlerts) alertas pendentes"
                                 + (criticalAlerts > 0 ? " (\(criticalAlerts) crítico\(criticalAlerts == 1 ? "" : "s"))" : ""))
            }
        }

        if !failedSources.isEmpty {
            sentences.append("Sem resposta de: \(failedSources.joined(separator: ", "))")
        }
        return sentences.joined(separator: ". ") + "."
    }

    private static func problemList(_ items: [String]) -> String {
        "\(items.count) com problema: \(names(items))"
    }

    private static func names(_ items: [String], limit: Int = 3) -> String {
        let shown = items.prefix(limit).joined(separator: ", ")
        return items.count > limit ? shown + " e mais \(items.count - limit)" : shown
    }
}

enum HomelabScanner {
    enum Source: CaseIterable {
        case system, docker, systemd, alerts

        var label: String {
            switch self {
            case .system: "sistema"
            case .docker: "Docker"
            case .systemd: "systemd"
            case .alerts: "alertas"
            }
        }
    }

    /// Monta o resumo a partir das respostas (puro, testável).
    static func summarize(system: SystemStatus?,
                          docker: VisionDockerStatus?,
                          systemd: VisionSystemdStatus?,
                          triggers: [VisionAlertTrigger]?) -> HomelabScanSummary {
        var summary = HomelabScanSummary()
        summary.hostname = system?.hostname
        summary.cpuPercent = system?.cpu?.usagePercent
        summary.temperatureC = system?.cpu?.temperatureC

        if let containers = docker?.containers {
            summary.containersTotal = containers.count
            summary.containersRunning = containers.filter { $0.state.lowercased() == "running" }.count
            summary.unhealthyContainers = containers.filter { container in
                container.state.lowercased() != "running"
                    || container.health?.status.lowercased() == "unhealthy"
            }.map { $0.names.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")) }
        }

        if let services = systemd?.services {
            summary.failedServices = services.filter { $0.activeState.lowercased() == "failed" }.map(\.service)
        }

        if let triggers {
            let pending = triggers.filter { !$0.acknowledged }
            summary.pendingAlerts = pending.count
            summary.criticalAlerts = pending.filter {
                AlertSeverity(value: $0.value, threshold: $0.threshold) == .critical
            }.count
        }

        var failed: [Source] = []
        if system == nil { failed.append(.system) }
        if docker == nil { failed.append(.docker) }
        if systemd == nil { failed.append(.systemd) }
        if triggers == nil { failed.append(.alerts) }
        summary.failedSources = failed.map(\.label)
        return summary
    }

    /// Busca as quatro fontes em paralelo; avança `progress` por fonte concluída.
    static func scan(progress: Progress? = nil) async -> HomelabScanSummary {
        let api = try? VisionAPIClient.shared
        async let system: SystemStatus? = try? await api?.fetch("api/system/status")
        async let docker: VisionDockerStatus? = try? await api?.fetch("api/docker/status?health=1")
        async let systemd: VisionSystemdStatus? = try? await api?.fetch("api/systemd/status")
        async let triggers: [VisionAlertTrigger]? = try? VisionAlertsAPI.fetchTriggers()

        let systemValue = await system
        progress?.completedUnitCount += 1
        let dockerValue = await docker
        progress?.completedUnitCount += 1
        let systemdValue = await systemd
        progress?.completedUnitCount += 1
        let triggerValues = await triggers
        progress?.completedUnitCount += 1

        if let triggerValues {
            let entities = AlertEntityMapper.entities(from: triggerValues, host: systemValue?.hostname)
            await AlertSpotlightIndexer.shared.donate(entities)
        }
        return summarize(system: systemValue, docker: dockerValue, systemd: systemdValue, triggers: triggerValues)
    }
}

/// "Scan do homelab": atualiza sistema, infraestrutura e alertas em segundo
/// plano (LongRunningIntent, visionOS 27) e devolve um resumo.
struct HomelabScanIntent: LongRunningIntent {
    static let title: LocalizedStringResource = "Scan do homelab"
    static let description = IntentDescription("Consulta sistema, Docker, systemd e alertas do MeuLab e devolve um resumo.")
    static let supportedModes: IntentModes = .background

    init() {}

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let progress = self.progress
        progress.totalUnitCount = Int64(HomelabScanner.Source.allCases.count)
        let summary = try await performBackgroundTask {
            await HomelabScanner.scan(progress: progress)
        }
        LabStatusSnippetIntent.reload()
        return .result(value: summary.text, dialog: IntentDialog(stringLiteral: summary.text))
    }
}
