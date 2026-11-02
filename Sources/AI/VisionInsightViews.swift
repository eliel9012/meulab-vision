import SwiftUI

/// Estado de um pedido ao modelo (resumo ou pergunta).
enum VisionInsightState: Equatable {
    case idle
    case loading
    case result(String)
    case failure(String)
}

/// Cartão com o resultado da Apple Intelligence (carregando/texto/erro).
struct VisionInsightResultCard: View {
    let title: String
    let state: VisionInsightState
    var onDismiss: (() -> Void)?

    var body: some View {
        if state != .idle {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(title, systemImage: "apple.intelligence").font(.headline)
                    Spacer()
                    if let onDismiss, state != .loading {
                        Button("Fechar", systemImage: "xmark", action: onDismiss)
                            .labelStyle(.iconOnly)
                            .buttonStyle(.plain)
                    }
                }
                switch state {
                case .idle: EmptyView()
                case .loading: ProgressView("Gerando…")
                case .result(let text):
                    Text(text).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                case .failure(let message):
                    Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
            .accessibilityElement(children: .combine)
        }
    }
}

/// Botão "Resumir" que some em aparelhos sem Apple Intelligence e fica
/// desabilitado (com dica) quando o modelo não está pronto.
struct VisionInsightButton: View {
    let title: String
    let availability: VisionInsightAvailability
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        if !availability.hidesFeature {
            Button(title, systemImage: "apple.intelligence", action: action)
                .disabled(!availability.isAvailable || isLoading)
                .help(availability.message ?? title)
        }
    }
}

/// "Pergunte ao MeuLab": pergunta livre sobre a telemetria do `VisionLabStore`.
struct VisionAskLabView: View {
    @Environment(VisionLabStore.self) private var lab
    var cpuHistory: VisionCPUHistory?

    @State private var question = ""
    @State private var state: VisionInsightState = .idle
    @State private var availability: VisionInsightAvailability = .available

    static let suggestions = [
        "O servidor está saudável?",
        "Por que a CPU está alta?",
        "Quanto espaço livre tenho em disco?"
    ]

    var body: some View {
        Group {
            if !availability.hidesFeature {
                VStack(alignment: .leading, spacing: 14) {
                    Label("Pergunte ao MeuLab", systemImage: "apple.intelligence").font(.title2.bold())
                    if let message = availability.message {
                        Label(message, systemImage: "info.circle").foregroundStyle(.secondary)
                    } else {
                        HStack {
                            TextField("Ex.: a temperatura está normal?", text: $question)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit(ask)
                            Button("Perguntar", systemImage: "paperplane.fill", action: ask)
                                .disabled(VisionInsightPrompt.sanitizedQuestion(question).isEmpty || state == .loading)
                        }
                        ScrollView(.horizontal) {
                            HStack {
                                ForEach(Self.suggestions, id: \.self) { suggestion in
                                    Button(suggestion) { question = suggestion; ask() }
                                        .buttonStyle(.bordered)
                                        .disabled(state == .loading)
                                }
                            }
                        }
                        .scrollIndicators(.hidden)
                        VisionInsightResultCard(title: "Resposta", state: state) { state = .idle }
                    }
                }
                .padding(18)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
                .offset(z: SpatialDepth.card)
            }
        }
        .task { availability = VisionInsightService.availability }
    }

    private func ask() {
        let context = VisionInsightPrompt.telemetryContext(
            system: lab.system, processes: lab.processes, partitions: lab.partitions,
            interfaces: lab.interfaces, cpuHistory: cpuHistory)
        let question = question
        state = .loading
        Task {
            do {
                state = .result(try await VisionInsightService.answer(question: question, context: context))
            } catch {
                state = .failure(error.localizedDescription)
            }
        }
    }
}
