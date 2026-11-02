import Foundation
import FoundationModels

/// Estado do modelo on-device, já traduzido para a UI.
enum VisionInsightAvailability: Equatable, Sendable {
    case available
    /// `hidesFeature`: aparelho sem suporte → nem mostra o botão.
    case unavailable(message: String, hidesFeature: Bool)

    var isAvailable: Bool { self == .available }

    var hidesFeature: Bool {
        if case .unavailable(_, let hides) = self { return hides }
        return false
    }

    var message: String? {
        if case .unavailable(let message, _) = self { return message }
        return nil
    }

    static func from(_ availability: SystemLanguageModel.Availability) -> VisionInsightAvailability {
        switch availability {
        case .available:
            return .available
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return .unavailable(message: "Este dispositivo não suporta Apple Intelligence.", hidesFeature: true)
            case .appleIntelligenceNotEnabled:
                return .unavailable(message: "Ative a Apple Intelligence em Ajustes para usar os resumos.", hidesFeature: false)
            case .modelNotReady:
                return .unavailable(message: "O modelo da Apple Intelligence ainda está sendo preparado. Tente mais tarde.", hidesFeature: false)
            @unknown default:
                return .unavailable(message: "Apple Intelligence indisponível no momento.", hidesFeature: false)
            }
        @unknown default:
            return .unavailable(message: "Apple Intelligence indisponível no momento.", hidesFeature: false)
        }
    }
}

enum VisionInsightError: LocalizedError {
    case unavailable(String)
    case emptyInput(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let message), .emptyInput(let message): message
        }
    }
}

/// Resumos/respostas via Foundation Models (modelo on-device do sistema).
/// Cada chamada usa uma sessão nova: os pedidos são independentes e isso
/// evita acumular transcript na janela de contexto pequena.
enum VisionInsightService {
    @MainActor
    static var availability: VisionInsightAvailability {
        .from(SystemLanguageModel.default.availability)
    }

    @MainActor
    static func respond(to prompt: String, instructions: String) async throws -> String {
        let availability = availability
        guard availability.isAvailable else {
            throw VisionInsightError.unavailable(availability.message ?? "Apple Intelligence indisponível.")
        }
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: Prompt(prompt))
        return VisionInsightPrompt.cleanedResponse(response.content)
    }

    @MainActor
    static func summarizeAlerts(_ triggers: [VisionAlertTrigger]) async throws -> String {
        guard let prompt = VisionInsightPrompt.alertsPrompt(triggers: triggers) else {
            return "Nenhum alerta ativo no momento. Tudo tranquilo."
        }
        return try await respond(to: prompt, instructions: VisionInsightPrompt.alertsInstructions)
    }

    @MainActor
    static func summarizeLogs(container: String, logs: String) async throws -> String {
        guard let prompt = VisionInsightPrompt.logsPrompt(container: container, logs: logs) else {
            throw VisionInsightError.emptyInput("Sem linhas de log para resumir.")
        }
        do {
            return try await respond(to: prompt, instructions: VisionInsightPrompt.logsInstructions)
        } catch let error as LanguageModelSession.GenerationError {
            // Linhas densas podem estourar a janela mesmo dentro do limite: tenta só o fim.
            guard case .exceededContextWindowSize = error,
                  let shorter = VisionInsightPrompt.logsPrompt(
                    container: container, logs: logs,
                    maxCharacters: VisionInsightPrompt.maxLogCharacters / 2) else { throw error }
            return try await respond(to: shorter, instructions: VisionInsightPrompt.logsInstructions)
        }
    }

    @MainActor
    static func answer(question: String, context: String) async throws -> String {
        guard let prompt = VisionInsightPrompt.questionPrompt(question: question, context: context) else {
            throw VisionInsightError.emptyInput(
                context.isEmpty ? "Telemetria ainda não carregada." : "Digite uma pergunta.")
        }
        return try await respond(to: prompt, instructions: VisionInsightPrompt.telemetryInstructions)
    }
}
