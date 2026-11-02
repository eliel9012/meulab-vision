import Foundation
import Observation
import OSLog
import UserNotifications

/// Notificações locais para disparos de alerta novos e não reconhecidos.
/// - Alimentado pelo poll leve do mission-control e pela tela de Alertas.
/// - Primeira carga da sessão só semeia o registro (sem notificação em massa).
/// - Ação "Reconhecer" chama a API de ack; toque abre a seção Alertas.
@MainActor
@Observable
final class VisionAlertNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = VisionAlertNotifier()

    /// Sobe a cada reconhecimento feito pela notificação; a tela de Alertas recarrega.
    private(set) var acknowledgeRevision = 0

    @ObservationIgnored private let logger = Logger(subsystem: "fun.meulab.vision", category: "alerts")

    /// Acima disso, um delta vira uma única notificação-resumo.
    static let individualLimit = 3
    /// Evita buscas duplicadas quando há mais de um poller (várias janelas).
    static let minimumPollInterval: Duration = .seconds(20)

    private let defaults: UserDefaults
    private var ledger: AlertNotificationLedger
    private var seededThisSession = false
    private var authorizationChecked = false
    private var polling = false
    private var lastPoll: ContinuousClock.Instant?
    private var configured = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.ledger = AlertNotificationLedger.load(from: defaults)
        super.init()
    }

    private var center: UNUserNotificationCenter { .current() }

    /// Registra delegate e a categoria com a ação "Reconhecer". Chamar no launch.
    func configure() {
        guard !configured else { return }
        configured = true
        center.delegate = self
        let acknowledge = UNNotificationAction(identifier: AlertNotificationAction.acknowledgeActionID,
                                               title: "Reconhecer",
                                               options: [])
        let category = UNNotificationCategory(identifier: AlertNotificationAction.categoryID,
                                              actions: [acknowledge],
                                              intentIdentifiers: [],
                                              options: [])
        center.setNotificationCategories([category])
    }

    /// Poll leve chamado pelo mission-control enquanto ativo.
    func poll() async {
        let now = ContinuousClock.now
        if polling { return }
        if let lastPoll, now - lastPoll < Self.minimumPollInterval { return }
        polling = true
        defer { polling = false }
        do {
            let triggers = try await VisionAlertsAPI.fetchTriggers()
            lastPoll = now
            await ingest(triggers)
        } catch {
            logger.error("Poll de alertas falhou: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Processa uma lista recém-buscada (do poll ou da tela de Alertas).
    func ingest(_ triggers: [VisionAlertTrigger]) async {
        AlertSpotlightIndexer.shared.donate(triggers: triggers)
        let notify = seededThisSession
        seededThisSession = true
        let fresh = ledger.ingest(triggers, notify: notify)
        ledger.save(to: defaults)
        await requestAuthorizationIfNeeded()
        guard !fresh.isEmpty else { return }
        if fresh.count > Self.individualLimit {
            await postSummary(count: fresh.count)
        } else {
            for trigger in fresh { await post(trigger) }
        }
    }

    /// Remove o banner já entregue de um alerta reconhecido no app.
    func clearDelivered(alertID: String) {
        center.removeDeliveredNotifications(withIdentifiers: [AlertNotificationAction.requestID(for: alertID)])
    }

    // MARK: - Autorização / envio

    /// Pede autorização só enquanto o status ainda é `.notDetermined` (uma vez).
    private func requestAuthorizationIfNeeded() async {
        // UI tests: the system prompt would sit on top of the window.
        guard !UserDefaults.standard.bool(forKey: "skipNotificationPrompt") else { return }
        guard !authorizationChecked else { return }
        authorizationChecked = true
        let status = await center.notificationSettings().authorizationStatus
        guard status == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    private func post(_ trigger: VisionAlertTrigger) async {
        let content = UNMutableNotificationContent()
        content.title = trigger.ruleName
        content.body = trigger.message
        content.sound = .default
        content.categoryIdentifier = AlertNotificationAction.categoryID
        content.threadIdentifier = "meulab-alerts"
        content.userInfo = [AlertNotificationAction.alertIDKey: trigger.id]
        let request = UNNotificationRequest(identifier: AlertNotificationAction.requestID(for: trigger.id),
                                            content: content, trigger: nil)
        try? await center.add(request)
    }

    private func postSummary(count: Int) async {
        let content = UNMutableNotificationContent()
        content.title = "MeuLab"
        content.body = "\(count) novos alertas não reconhecidos."
        content.sound = .default
        content.threadIdentifier = "meulab-alerts"
        let request = UNNotificationRequest(identifier: "alert-summary-\(UUID().uuidString)",
                                            content: content, trigger: nil)
        try? await center.add(request)
    }

    /// O banner some ao tocar a ação: sem isso a falha pareceria um reconhecimento feito.
    private func postAcknowledgeFailure(alertID: String) async {
        let content = UNMutableNotificationContent()
        content.title = "Não foi possível reconhecer"
        content.body = "O alerta continua pendente. Abra o MeuLab para tentar de novo."
        content.threadIdentifier = "meulab-alerts"
        content.userInfo = [AlertNotificationAction.alertIDKey: alertID]
        let request = UNNotificationRequest(identifier: "alert-ack-failed-\(alertID)",
                                            content: content, trigger: nil)
        try? await center.add(request)
    }

    private func handle(_ action: AlertNotificationAction) async {
        switch action {
        case .acknowledge(let id):
            do {
                try await VisionAlertsAPI.acknowledge(id)
                clearDelivered(alertID: id)
                acknowledgeRevision &+= 1
            } catch {
                await postAcknowledgeFailure(alertID: id)
            }
        case .openAlerts:
            VisionDeepLinkRouter.shared.open(.alerts)
        case .ignore:
            break
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification)
        async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let action = AlertNotificationAction.resolve(
            actionIdentifier: response.actionIdentifier,
            alertID: response.notification.request.content.userInfo[AlertNotificationAction.alertIDKey] as? String)
        await handle(action)
    }
}
