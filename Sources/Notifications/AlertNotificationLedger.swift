import Foundation

/// Registro persistente dos ids de disparo já vistos, para notificar cada
/// alerta uma única vez (inclusive entre execuções do app).
struct AlertNotificationLedger: Equatable, Sendable {
    static let defaultsKey = "alerts.notifiedTriggerIDs"
    /// Bem acima do `limit` da API (40): um id só sai daqui depois de sair da janela buscada.
    static let capacity = 300

    private(set) var knownIDs: [String]

    init(knownIDs: [String] = []) {
        self.knownIDs = Array(knownIDs.suffix(Self.capacity))
    }

    func contains(_ id: String) -> Bool { knownIDs.contains(id) }

    /// Registra todos os ids recebidos e devolve os disparos novos e não
    /// reconhecidos. Com `notify == false` (primeira carga) só semeia.
    mutating func ingest(_ triggers: [VisionAlertTrigger], notify: Bool) -> [VisionAlertTrigger] {
        var known = Set(knownIDs)
        var fresh: [VisionAlertTrigger] = []
        for trigger in triggers where known.insert(trigger.id).inserted {
            knownIDs.append(trigger.id)
            if notify, !trigger.acknowledged { fresh.append(trigger) }
        }
        if knownIDs.count > Self.capacity {
            knownIDs.removeFirst(knownIDs.count - Self.capacity)
        }
        return fresh
    }

    static func load(from defaults: UserDefaults) -> AlertNotificationLedger {
        AlertNotificationLedger(knownIDs: defaults.stringArray(forKey: defaultsKey) ?? [])
    }

    func save(to defaults: UserDefaults) {
        defaults.set(knownIDs, forKey: Self.defaultsKey)
    }
}

/// Resposta do usuário a uma notificação de alerta.
enum AlertNotificationAction: Equatable, Sendable {
    static let categoryID = "MEULAB_ALERT"
    static let acknowledgeActionID = "MEULAB_ALERT_ACK"
    static let alertIDKey = "alertID"
    /// `UNNotificationDefaultActionIdentifier` (toque no banner).
    static let defaultActionID = "com.apple.UNNotificationDefaultActionIdentifier"

    case acknowledge(String)
    case openAlerts
    case ignore

    static func resolve(actionIdentifier: String, alertID: String?) -> AlertNotificationAction {
        switch actionIdentifier {
        case acknowledgeActionID:
            guard let alertID, !alertID.isEmpty else { return .openAlerts }
            return .acknowledge(alertID)
        case defaultActionID: return .openAlerts
        default: return .ignore
        }
    }

    static func requestID(for alertID: String) -> String { "alert-\(alertID)" }
}
