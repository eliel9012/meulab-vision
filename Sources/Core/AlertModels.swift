import Foundation

struct VisionAlertRule: Decodable, Sendable, Identifiable {
    let id: String
    let name: String
    let type: String
    let threshold: Double
    let enabled: Bool
    let lastTriggered: String?
}

struct VisionAlertTrigger: Decodable, Sendable, Identifiable {
    let id: String
    let ruleName: String
    let triggeredAt: String
    let value: Double
    let threshold: Double
    let message: String
    let acknowledged: Bool
}

/// Chamadas de alertas compartilhadas entre a tela, notificações e App Intents.
enum VisionAlertsAPI {
    static let triggerLimit = 40

    static func fetchTriggers(limit: Int = triggerLimit) async throws -> [VisionAlertTrigger] {
        try await VisionAPIClient.shared.fetch("api/alerts/triggers",
                                               query: [URLQueryItem(name: "limit", value: String(limit))])
    }

    static func fetchRules() async throws -> [VisionAlertRule] {
        try await VisionAPIClient.shared.fetch("api/alerts/rules")
    }

    @discardableResult
    static func acknowledge(_ id: String) async throws -> VisionAlertTrigger {
        try await VisionAPIClient.shared.post("api/alerts/triggers/\(VisionQuery.pathSegment(id))/ack")
    }
}
