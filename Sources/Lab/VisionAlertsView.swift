import SwiftUI

struct VisionAlertsView: View {
    @State private var rules: [VisionAlertRule] = []
    @State private var triggers: [VisionAlertTrigger] = []
    @State private var error: String?
    @State private var loading = false
    /// Pedido feito durante outra busca: roda de novo ao terminar (a resposta em voo pode ser velha).
    @State private var refreshPending = false
    @State private var acknowledging: Set<String> = []
    @State private var updatedAt: Date?
    @State private var summary: VisionInsightState = .idle
    @State private var insightAvailability: VisionInsightAvailability = .available
    @State private var chimeGate = AlertChimeGate()
    /// Alerta aberto via deep link/OpenAlertIntent: destacado e rolado até a vista.
    @State private var focusedID: String?
    @State private var triggersLoaded = false
    @Environment(VisionDeepLinkRouter.self) private var router

    static let focusDuration: Duration = .seconds(6)

    /// Alerta pedido fora da janela da API: sem aviso, a tela só pareceria ignorar o pedido.
    static func isFocusMissing(focusedID: String?, loaded: Bool, triggerIDs: [String]) -> Bool {
        guard let focusedID, loaded else { return false }
        return !triggerIDs.contains(focusedID)
    }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Label("Alertas", systemImage: "bell.badge").font(.largeTitle.bold())
                    Spacer()
                    VisionInsightButton(title: "Resumir", availability: insightAvailability,
                                        isLoading: summary == .loading) { Task { await summarize() } }
                        .disabled(VisionInsightPrompt.activeTriggers(triggers).isEmpty)
                }
                if let message = insightAvailability.message, !insightAvailability.hidesFeature {
                    Label(message, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
                }
                VisionInsightResultCard(title: "Resumo dos alertas ativos", state: summary) { summary = .idle }
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                if Self.isFocusMissing(focusedID: focusedID, loaded: triggersLoaded, triggerIDs: triggers.map(\.id)) {
                    Label("Este alerta não está mais entre os \(VisionAlertsAPI.triggerLimit) disparos recentes.",
                          systemImage: "clock.arrow.circlepath")
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 14) {
                    countCard("Regras ativas", rules.filter(\.enabled).count, symbol: "checkmark.shield")
                    countCard("Não reconhecidos", triggers.filter { !$0.acknowledged }.count, symbol: "bell.fill")
                }
                section("Disparos recentes", symbol: "bolt.badge.clock") {
                    if triggers.isEmpty {
                        empty("Nenhum disparo registrado.")
                    } else {
                        ForEach(triggers) { trigger in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: trigger.acknowledged ? "checkmark.circle" : "exclamationmark.circle.fill")
                                    .foregroundStyle(trigger.acknowledged ? .green : .orange)
                                    .accessibilityLabel(trigger.acknowledged ? "Reconhecido" : "Não reconhecido")
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(trigger.ruleName).font(.headline)
                                    Text(trigger.message).font(.callout)
                                    Text("Valor \(trigger.value.formatted()) · limite \(trigger.threshold.formatted())")
                                        .font(.caption).foregroundStyle(.secondary)
                                    Text(trigger.triggeredAt.replacingOccurrences(of: "T", with: " "))
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if !trigger.acknowledged {
                                    Button("Reconhecer") { Task { await acknowledge(trigger) } }
                                        .disabled(acknowledging.contains(trigger.id))
                                }
                            }
                            .padding(14)
                            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                            .overlay {
                                if focusedID == trigger.id {
                                    RoundedRectangle(cornerRadius: 12).strokeBorder(.orange, lineWidth: 2)
                                }
                            }
                            .id(trigger.id)
                        }
                    }
                }
                section("Regras do servidor", symbol: "slider.horizontal.3") {
                    if rules.isEmpty {
                        empty("Nenhuma regra cadastrada.")
                    } else {
                        ForEach(rules) { rule in
                            HStack {
                                Image(systemName: rule.enabled ? "checkmark.circle.fill" : "pause.circle")
                                    .foregroundStyle(rule.enabled ? .green : .secondary)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(rule.name).font(.headline)
                                    Text("\(rule.type.replacingOccurrences(of: "_", with: " ")) · limite \(rule.threshold.formatted())")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(rule.enabled ? "Ativa" : "Pausada")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(14)
                            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                if let updatedAt {
                    Text("Atualizado \(updatedAt.formatted(date: .omitted, time: .standard)) · MeuLab API")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: router.focusedAlertID, initial: true) { _, id in
            if id != nil { focusedID = router.consumeFocusedAlert() }
            scrollToFocused(proxy)
        }
        .onChange(of: triggers.map(\.id)) { _, _ in scrollToFocused(proxy) }
        .onChange(of: VisionAlertNotifier.shared.acknowledgeRevision) { _, _ in Task { await refresh() } }
        // Conta só depois da lista chegar, para o destaque não sumir antes de aparecer.
        .task(id: "\(focusedID ?? "")-\(triggersLoaded)") {
            guard focusedID != nil, triggersLoaded else { return }
            try? await Task.sleep(for: Self.focusDuration)
            if !Task.isCancelled { focusedID = nil }
        }
        }
        .padding(28)
        .background(SceneIdentifierReader { AlertChimePlayer.shared.anchor(toScene: $0) })
        .toolbar {
            ToolbarItemGroup(placement: .bottomOrnament) {
                if loading { ProgressView() }
                Button("Atualizar", systemImage: "arrow.clockwise") { Task { await refresh() } }
            }
        }
        .polling(every: .seconds(30)) { await refresh() }
        .task { insightAvailability = VisionInsightService.availability }
    }

    private func scrollToFocused(_ proxy: ScrollViewProxy) {
        guard let focusedID, triggers.contains(where: { $0.id == focusedID }) else { return }
        withAnimation { proxy.scrollTo(focusedID, anchor: .center) }
    }

    private func summarize() async {
        summary = .loading
        do {
            summary = .result(try await VisionInsightService.summarizeAlerts(triggers))
        } catch {
            summary = .failure(error.localizedDescription)
        }
    }

    private func section<Content: View>(_ title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol).font(.title2.bold())
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
        .offset(z: SpatialDepth.card)
    }

    private func countCard(_ title: String, _ count: Int, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
            Text("\(count)").font(.title.bold()).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
        .depthCard()
    }

    private func empty(_ text: String) -> some View {
        Text(text).foregroundStyle(.secondary).padding(12)
    }

    private func refresh() async {
        guard !loading else {
            refreshPending = true
            return
        }
        loading = true
        defer { loading = false }
        repeat {
            refreshPending = false
            await fetchRulesAndTriggers()
        } while refreshPending
    }

    /// Fontes independentes: falhar uma não apaga nem esconde a outra.
    private func fetchRulesAndTriggers() async {
        async let rulesTask = Self.attempt { try await VisionAlertsAPI.fetchRules() }
        async let triggersTask = Self.attempt { try await VisionAlertsAPI.fetchTriggers() }
        let (rulesResult, triggersResult) = await (rulesTask, triggersTask)

        var failures: [String] = []
        switch rulesResult {
        case .success(let value): rules = value
        case .failure(let failure): failures.append("Regras: \(failure.localizedDescription)")
        }
        switch triggersResult {
        case .success(let value):
            triggers = value
            triggersLoaded = true
            let unacknowledged = Set(value.filter { !$0.acknowledged }.map(\.id))
            if chimeGate.shouldChime(unacknowledgedIDs: unacknowledged) { AlertChimePlayer.shared.play() }
            // Mesmo polling alimenta as notificações locais (dedup no notifier).
            await VisionAlertNotifier.shared.ingest(value)
        case .failure(let failure):
            failures.append("Disparos: \(failure.localizedDescription)")
        }
        error = failures.isEmpty ? nil : failures.joined(separator: "\n")
        if failures.isEmpty { updatedAt = Date() }
    }

    private static func attempt<Value: Sendable>(
        _ operation: @Sendable () async throws -> Value
    ) async -> Result<Value, any Error> {
        do { return .success(try await operation()) }
        catch { return .failure(error) }
    }

    private func acknowledge(_ trigger: VisionAlertTrigger) async {
        acknowledging.insert(trigger.id)
        defer { acknowledging.remove(trigger.id) }
        do {
            let updated = try await VisionAlertsAPI.acknowledge(trigger.id)
            // O botão some já, mesmo que a atualização seguinte falhe.
            if let index = triggers.firstIndex(where: { $0.id == updated.id }) { triggers[index] = updated }
            VisionAlertNotifier.shared.clearDelivered(alertID: trigger.id)
            await refresh()
        } catch { self.error = error.localizedDescription }
    }
}
