import AppIntents
import Foundation

// MARK: - Seções

/// Espelho de `VisionSection` para App Intents. `rawValue` = nome do case =
/// id do deep link (`meulabvision://section/<rawValue>`).
enum SectionAppEnum: String, AppEnum, CaseIterable, Sendable {
    case radar, trip, analytics, alerts, system, infrastructure, radio, weather, acars, series

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Seção" }

    static var caseDisplayRepresentations: [SectionAppEnum: DisplayRepresentation] {
        [
            .radar: DisplayRepresentation(title: "Radar ADS-B", image: .init(systemName: "airplane")),
            .trip: DisplayRepresentation(title: "Viagem", image: .init(systemName: "suitcase.rolling.fill")),
            .analytics: DisplayRepresentation(title: "Analytics", image: .init(systemName: "chart.xyaxis.line")),
            .alerts: DisplayRepresentation(title: "Alertas", image: .init(systemName: "bell.badge")),
            .system: DisplayRepresentation(title: "Sistema", image: .init(systemName: "cpu")),
            .infrastructure: DisplayRepresentation(title: "Infraestrutura", image: .init(systemName: "server.rack")),
            .radio: DisplayRepresentation(title: "Rádio", image: .init(systemName: "radio")),
            .weather: DisplayRepresentation(title: "Clima", image: .init(systemName: "cloud.sun")),
            .acars: DisplayRepresentation(title: "ACARS", image: .init(systemName: "waveform.path")),
            .series: DisplayRepresentation(title: "Séries", image: .init(systemName: "film.stack")),
        ]
    }

    init(_ section: VisionSection) {
        switch section {
        case .radar: self = .radar
        case .trip: self = .trip
        case .analytics: self = .analytics
        case .alerts: self = .alerts
        case .system: self = .system
        case .infrastructure: self = .infrastructure
        case .radio: self = .radio
        case .weather: self = .weather
        case .acars: self = .acars
        case .series: self = .series
        }
    }

    var section: VisionSection {
        switch self {
        case .radar: .radar
        case .trip: .trip
        case .analytics: .analytics
        case .alerts: .alerts
        case .system: .system
        case .infrastructure: .infrastructure
        case .radio: .radio
        case .weather: .weather
        case .acars: .acars
        case .series: .series
        }
    }
}

// MARK: - Abrir seção

/// Abre o app na seção pedida; no radar o mission-control também abre o volume.
struct OpenSectionIntent: OpenIntent {
    static let title: LocalizedStringResource = "Abrir seção do MeuLab"
    static let description = IntentDescription("Abre o MeuLab Vision na seção escolhida. O radar abre também o volume 3D.")
    static let supportedModes: IntentModes = .foreground(.immediate)

    @Parameter(title: "Seção")
    var target: SectionAppEnum

    static var parameterSummary: some ParameterSummary {
        Summary("Abrir \(\.$target)")
    }

    init() {}

    init(target: SectionAppEnum) {
        self.target = target
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        VisionDeepLinkRouter.shared.open(target.section)
        return .result()
    }
}

// MARK: - Consultas (sem abrir o app)

struct VisionSystemStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Status do laboratório"
    static let description = IntentDescription("Resume CPU, memória, temperatura e uptime do servidor do MeuLab.")
    static let supportedModes: IntentModes = .background
    static let allowedExecutionTargets: IntentExecutionTargets = [.main]

    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            let status: SystemStatus = try await VisionAPIClient.shared.fetch("api/system/status")
            return .result(dialog: IntentDialog(stringLiteral: VisionIntentDialogs.system(status)))
        } catch {
            return .result(dialog: "Não consegui consultar o laboratório agora.")
        }
    }
}

struct VisionPendingAlertsIntent: AppIntent {
    static let title: LocalizedStringResource = "Alertas pendentes"
    static let description = IntentDescription("Informa quantos alertas do MeuLab ainda não foram reconhecidos.")
    static let supportedModes: IntentModes = .background
    static let allowedExecutionTargets: IntentExecutionTargets = [.main]

    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        do {
            let triggers = try await VisionAlertsAPI.fetchTriggers()
            let pending = triggers.filter { !$0.acknowledged }
            return .result(value: pending.count,
                           dialog: IntentDialog(stringLiteral: VisionIntentDialogs.alerts(pending)))
        } catch {
            throw VisionIntentError(errorDescription: "Não consegui consultar os alertas agora.")
        }
    }
}

struct VisionAircraftCountIntent: AppIntent {
    static let title: LocalizedStringResource = "Aeronaves no radar"
    static let description = IntentDescription("Conta as aeronaves rastreadas agora pelo radar ADS-B do MeuLab.")
    static let supportedModes: IntentModes = .background
    static let allowedExecutionTargets: IntentExecutionTargets = [.main]

    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        do {
            let data = try await ADSBClient().fetch()
            let count = try AircraftDecoder.decode(data).aircraft.count
            return .result(value: count, dialog: IntentDialog(stringLiteral: VisionIntentDialogs.aircraft(count)))
        } catch {
            throw VisionIntentError(errorDescription: "Não foi possível conectar ao radar agora.")
        }
    }
}

/// Falha de consulta: um atalho que usa o valor não pode confundir erro com "zero".
struct VisionIntentError: LocalizedError {
    let errorDescription: String?
}

/// Textos falados/mostrados pelos intents (puros, testáveis).
enum VisionIntentDialogs {
    static func system(_ status: SystemStatus) -> String {
        var parts = ["\(status.hostname) no ar"]
        if let uptime = status.uptime?.formatted { parts[0] += " há \(uptime)" }
        if let cpu = status.cpu?.usagePercent { parts.append("CPU \(Int(cpu))%") }
        if let memory = status.memory?.usedPercent { parts.append("memória \(Int(memory))%") }
        if let temperature = status.cpu?.temperatureC { parts.append("\(Int(temperature))°C") }
        return parts.joined(separator: ", ") + "."
    }

    static func alerts(_ pending: [VisionAlertTrigger]) -> String {
        switch pending.count {
        case 0: return "Nenhum alerta pendente no MeuLab."
        case 1: return "1 alerta pendente: \(pending[0].ruleName)."
        default:
            let names = pending.prefix(3).map(\.ruleName).joined(separator: ", ")
            return "\(pending.count) alertas pendentes. Mais recentes: \(names)."
        }
    }

    static func aircraft(_ count: Int) -> String {
        switch count {
        case 0: "Nenhuma aeronave no radar agora."
        case 1: "O radar está rastreando 1 aeronave."
        default: "O radar está rastreando \(count) aeronaves."
        }
    }
}

// MARK: - Atalhos

struct VisionShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenSectionIntent(),
            phrases: [
                "Abrir \(\.$target) no \(.applicationName)",
                "Mostrar \(\.$target) no \(.applicationName)",
            ],
            shortTitle: "Abrir seção",
            systemImageName: "square.grid.2x2"
        )
        AppShortcut(
            intent: VisionSystemStatusIntent(),
            phrases: [
                "Status do \(.applicationName)",
                "Como está o \(.applicationName)",
            ],
            shortTitle: "Status do laboratório",
            systemImageName: "server.rack"
        )
        AppShortcut(
            intent: VisionPendingAlertsIntent(),
            phrases: [
                "Alertas do \(.applicationName)",
                "Tem alerta no \(.applicationName)",
            ],
            shortTitle: "Alertas pendentes",
            systemImageName: "bell.badge"
        )
        AppShortcut(
            intent: VisionAircraftCountIntent(),
            phrases: [
                "Quantos aviões no \(.applicationName)",
                "Quantas aeronaves no \(.applicationName)",
            ],
            shortTitle: "Aeronaves no radar",
            systemImageName: "dot.radiowaves.left.and.right"
        )
        AppShortcut(
            intent: LabStatusIntent(),
            phrases: [
                "Painel do \(.applicationName)",
                "Resumo do \(.applicationName)",
            ],
            shortTitle: "Status do MeuLab",
            systemImageName: "gauge.with.dots.needle.67percent"
        )
        AppShortcut(
            intent: HomelabScanIntent(),
            phrases: [
                "Scan do homelab no \(.applicationName)",
                "Varrer o homelab no \(.applicationName)",
            ],
            shortTitle: "Scan do homelab",
            systemImageName: "stethoscope"
        )
        AppShortcut(
            intent: OpenAlertIntent(),
            phrases: [
                "Abrir alerta \(\.$target) no \(.applicationName)",
            ],
            shortTitle: "Abrir alerta",
            systemImageName: "bell.and.waves.left.and.right"
        )
    }
}
