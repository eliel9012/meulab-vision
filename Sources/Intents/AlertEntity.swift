import AppIntents
import CoreSpotlight
import Foundation

// MARK: - Severidade

/// Severidade derivada de valor × limite (a API não manda severidade).
/// - abaixo do limite → informativo
/// - até 10% acima → atenção
/// - 10% ou mais acima → crítico
enum AlertSeverity: String, Sendable, Equatable, CaseIterable {
    case info, warning, critical

    static let criticalRatio = 1.1

    init(value: Double, threshold: Double) {
        if value < threshold {
            self = .info
        } else if threshold > 0, value >= threshold * Self.criticalRatio {
            self = .critical
        } else {
            self = .warning
        }
    }

    var label: String {
        switch self {
        case .info: "Informativo"
        case .warning: "Atenção"
        case .critical: "Crítico"
        }
    }

    var symbolName: String {
        switch self {
        case .info: "info.circle"
        case .warning: "exclamationmark.triangle"
        case .critical: "exclamationmark.octagon"
        }
    }
}

// MARK: - Entidade

/// Disparo de alerta exposto ao sistema (Shortcuts, Siri, Spotlight).
struct AlertEntity: IndexedEntity, Equatable {
    static let fallbackHost = "MeuLab"

    let id: String
    let title: String
    let message: String
    let severity: AlertSeverity
    let host: String
    let date: Date?
    let acknowledged: Bool

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Alerta do MeuLab", numericFormat: "\(placeholder: .int) alertas")
    }

    static var defaultQuery: AlertEntityQuery { AlertEntityQuery() }

    init(id: String, title: String, message: String, severity: AlertSeverity,
         host: String, date: Date?, acknowledged: Bool) {
        self.id = id
        self.title = title
        self.message = message
        self.severity = severity
        self.host = host
        self.date = date
        self.acknowledged = acknowledged
    }

    init(trigger: VisionAlertTrigger, host: String?) {
        let trimmedHost = host?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.init(id: trigger.id,
                  title: trigger.ruleName,
                  message: trigger.message,
                  severity: AlertSeverity(value: trigger.value, threshold: trigger.threshold),
                  host: trimmedHost.isEmpty ? Self.fallbackHost : trimmedHost,
                  date: Self.parseDate(trigger.triggeredAt),
                  acknowledged: trigger.acknowledged)
    }

    static func parseDate(_ string: String) -> Date? {
        Formatters.parseISO(string)
    }

    /// "Crítico · radar · CPU 93%" (+ "· reconhecido").
    var subtitle: String {
        var parts = [severity.label, host]
        if !message.isEmpty { parts.append(message) }
        if acknowledged { parts.append("reconhecido") }
        return parts.joined(separator: " · ")
    }

    var deepLink: URL { VisionDeepLink.url(forAlert: id) }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)",
                              subtitle: "\(subtitle)",
                              image: .init(systemName: severity.symbolName))
    }

    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = defaultAttributeSet
        attributes.title = title
        attributes.displayName = title
        attributes.contentDescription = subtitle
        attributes.keywords = ["alerta", "MeuLab", host, severity.label, title]
        attributes.contentCreationDate = date
        attributes.contentURL = deepLink
        return attributes
    }

    /// Reconhecidos não poluem a busca do Spotlight.
    var hideInSpotlight: Bool { acknowledged }
}

// MARK: - Mapeamento / ordenação (puro)

enum AlertEntityMapper {
    static func entities(from triggers: [VisionAlertTrigger], host: String?) -> [AlertEntity] {
        triggers.map { AlertEntity(trigger: $0, host: host) }
    }

    /// Pendentes primeiro; depois mais grave; depois mais recente.
    static func sortedForSuggestion(_ entities: [AlertEntity]) -> [AlertEntity] {
        entities.sorted { lhs, rhs in
            if lhs.acknowledged != rhs.acknowledged { return !lhs.acknowledged }
            let lRank = rank(lhs.severity), rRank = rank(rhs.severity)
            if lRank != rRank { return lRank > rRank }
            return (lhs.date ?? .distantPast) > (rhs.date ?? .distantPast)
        }
    }

    /// A lista da API só traz uma janela recente: um alerta mais antigo vindo do Spotlight
    /// ou de um atalho ainda precisa resolver, ou abri-lo falharia sem explicação.
    static func resolving(_ identifiers: [AlertEntity.ID], in entities: [AlertEntity]) -> [AlertEntity] {
        identifiers.map { id in
            entities.first { $0.id == id } ?? AlertEntity(
                id: id, title: "Alerta do MeuLab", message: "", severity: .info,
                host: AlertEntity.fallbackHost, date: nil, acknowledged: false)
        }
    }

    /// Ids já doados que saíram da lista e precisam sair do Spotlight.
    static func staleIDs(previous: [AlertEntity], current: [AlertEntity]) -> [AlertEntity.ID] {
        let kept = Set(current.map(\.id))
        return previous.map(\.id).filter { !kept.contains($0) }
    }

    static func matching(_ string: String, in entities: [AlertEntity]) -> [AlertEntity] {
        let needle = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return entities }
        return entities.filter { entity in
            [entity.title, entity.message, entity.host, entity.severity.label].contains {
                $0.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        }
    }

    private static func rank(_ severity: AlertSeverity) -> Int {
        switch severity {
        case .info: 0
        case .warning: 1
        case .critical: 2
        }
    }
}

// MARK: - Query

struct AlertEntityQuery: IndexedEntityQuery, EntityStringQuery {
    init() {}

    func entities(for identifiers: [AlertEntity.ID]) async throws -> [AlertEntity] {
        // API fora do ar também não pode impedir de abrir o alerta.
        AlertEntityMapper.resolving(identifiers, in: (try? await AlertEntityLoader.fetch()) ?? [])
    }

    func entities(matching string: String) async throws -> [AlertEntity] {
        AlertEntityMapper.matching(string, in: try await AlertEntityLoader.fetch())
    }

    func suggestedEntities() async throws -> [AlertEntity] {
        AlertEntityMapper.sortedForSuggestion(try await AlertEntityLoader.fetch())
    }

    func reindexEntities(for identifiers: [AlertEntity.ID],
                         indexDescription: CSSearchableIndexDescription) async throws {
        // Só alertas reais: o substituto de `entities(for:)` não pode entrar no índice.
        let wanted = Set(identifiers)
        let entities = try await AlertEntityLoader.fetch().filter { wanted.contains($0.id) }
        try await CSSearchableIndex.default().indexAppEntities(entities)
    }

    func reindexAllEntities(indexDescription: CSSearchableIndexDescription) async throws {
        let entities = try await AlertEntityLoader.fetch()
        try await CSSearchableIndex.default().deleteAppEntities(ofType: AlertEntity.self)
        try await CSSearchableIndex.default().indexAppEntities(entities)
    }
}

/// Busca alertas na API e já doa ao Spotlight.
enum AlertEntityLoader {
    static func currentHost() -> String? {
        WidgetSnapshot.load()?.system?.hostname
    }

    static func fetch() async throws -> [AlertEntity] {
        let triggers = try await VisionAlertsAPI.fetchTriggers()
        let entities = AlertEntityMapper.entities(from: triggers, host: currentHost())
        await AlertSpotlightIndexer.shared.donate(entities)
        return entities
    }
}

// MARK: - Spotlight

/// Doação de `AlertEntity` ao índice do Spotlight, sem repetir listas iguais.
@MainActor
final class AlertSpotlightIndexer {
    static let shared = AlertSpotlightIndexer()

    private var lastDonated: [AlertEntity] = []
    /// `lastDonated` não sobrevive ao relançamento: a primeira doação limpa o índice.
    private var indexIsInSync = false

    /// Chamado pelo poll do notifier e pelas queries.
    func donate(triggers: [VisionAlertTrigger]) {
        let entities = AlertEntityMapper.entities(from: triggers, host: AlertEntityLoader.currentHost())
        Task { await donate(entities) }
    }

    func donate(_ entities: [AlertEntity]) async {
        guard entities != lastDonated, CSSearchableIndex.isIndexingAvailable() else { return }
        let stale = AlertEntityMapper.staleIDs(previous: lastDonated, current: entities)
        lastDonated = entities
        let index = CSSearchableIndex.default()
        do {
            if !indexIsInSync {
                try await index.deleteAppEntities(ofType: AlertEntity.self)
            } else if !stale.isEmpty {
                try await index.deleteAppEntities(identifiedBy: stale, ofType: AlertEntity.self)
            }
            try await index.indexAppEntities(entities)
            indexIsInSync = true
        } catch {
            lastDonated = []
            indexIsInSync = false
        }
    }
}
