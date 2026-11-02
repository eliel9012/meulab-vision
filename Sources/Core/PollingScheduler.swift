import SwiftUI

/// Laço de polling único do app: roda `action`, dorme `interval`, repete até a task ser cancelada.
/// A integração com SwiftUI (`.polling`) reinicia/cancela o laço conforme `id` e `scenePhase`.
@MainActor
enum PollingScheduler {
    /// Só faz polling com a cena em primeiro plano; `.inactive`/`.background` pausam.
    nonisolated static func shouldPoll(_ phase: ScenePhase) -> Bool { phase == .active }

    /// Executa `action` imediatamente (se `immediately`) e depois a cada `interval`.
    /// Sai assim que a task corrente é cancelada (sleep lança `CancellationError`).
    static func run<C: Clock>(every interval: C.Duration,
                              clock: C,
                              immediately: Bool = true,
                              action: @MainActor () async -> Void) async {
        if immediately {
            guard !Task.isCancelled else { return }
            await action()
        }
        while !Task.isCancelled {
            do { try await clock.sleep(for: interval) } catch { return }
            guard !Task.isCancelled else { return }
            await action()
        }
    }

    static func run(every interval: Duration,
                    immediately: Bool = true,
                    action: @MainActor () async -> Void) async {
        await run(every: interval, clock: ContinuousClock(), immediately: immediately, action: action)
    }
}

/// Chave do `.task(id:)`: muda quando o id do chamador muda ou a cena entra/sai de `.active`.
struct PollingKey<ID: Equatable>: Equatable {
    let id: ID
    let active: Bool
}

private struct PollingModifier<ID: Equatable>: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    let interval: Duration
    let id: ID
    let immediately: Bool
    let action: @MainActor @Sendable () async -> Void

    func body(content: Content) -> some View {
        let active = PollingScheduler.shouldPoll(scenePhase)
        content.task(id: PollingKey(id: id, active: active)) {
            guard active else { return }
            await PollingScheduler.run(every: interval, immediately: immediately, action: action)
        }
    }
}

extension View {
    /// Polling ciente de `scenePhase`: pausa fora de `.active`, retoma (com execução imediata)
    /// ao voltar, e reinicia quando `id` muda. Cancelado automaticamente quando a view some.
    func polling<ID: Equatable>(every interval: Duration,
                                id: ID,
                                immediately: Bool = true,
                                action: @escaping @MainActor @Sendable () async -> Void) -> some View {
        modifier(PollingModifier(interval: interval, id: id, immediately: immediately, action: action))
    }

    func polling(every interval: Duration,
                 immediately: Bool = true,
                 action: @escaping @MainActor @Sendable () async -> Void) -> some View {
        polling(every: interval, id: 0, immediately: immediately, action: action)
    }
}
