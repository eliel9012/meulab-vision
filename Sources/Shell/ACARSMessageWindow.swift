import SwiftUI

/// Messages already loaded by VisionACARSView, keyed by id, so the pushed
/// "acars-message" window (which only receives the id) can render instantly
/// and then refresh the full detail from the API.
@MainActor
final class ACARSMessageCache {
    static let shared = ACARSMessageCache()
    private var items: [Int: ACARSItem] = [:]
    private let limit = 500

    func store(_ messages: [ACARSItem]) {
        for item in messages { items[item.id] = item }
        if items.count > limit {
            // Keep the newest ids (ACARS ids grow monotonically).
            for id in items.keys.sorted().prefix(items.count - limit) { items[id] = nil }
        }
    }

    func message(_ id: Int) -> ACARSItem? { items[id] }
}

/// Transient window opened with `pushWindow(id: "acars-message", value: id)`.
struct ACARSMessageWindowView: View {
    let messageID: Int?
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var detail: ACARSItem?
    @State private var error: String?

    var body: some View {
        Group {
            if let messageID {
                content(messageID)
            } else {
                ContentUnavailableView("Mensagem indisponível", systemImage: "envelope.badge",
                                       description: Text("Abra a mensagem pela seção ACARS."))
            }
        }
    }

    private func content(_ messageID: Int) -> some View {
        let message = detail ?? ACARSMessageCache.shared.message(messageID)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Label(message?.title ?? "Mensagem \(messageID)", systemImage: "envelope.open")
                    .font(.largeTitle.bold())
                if let error { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                if let message {
                    field("Horário", message.time)
                    field("Etiqueta", "\(message.label ?? "—") · \(message.labelDesc ?? "—")")
                    if let route = message.route { field("Rota", route) }
                    if let type = message.messageType { field("Tipo", type) }
                    if let station = message.stationId { field("Estação", station) }
                    if let eta = message.eta { field("ETA", eta) }
                    if let frequency = message.freqMhz { field("Frequência", "\(frequency) MHz") }
                    if let altitude = message.altitudeFt { field("Altitude", "\(altitude.formatted()) ft") }
                    if let lat = message.lat, let lon = message.lon { field("Posição", "\(lat), \(lon)") }
                    Text(message.text ?? "Sem texto decodificado")
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                } else if error == nil {
                    ProgressView("Carregando…")
                }
            }
            .padding(28)
        }
        .scrollInputBehavior(.enabled, for: .look)
        .toolbar {
            ToolbarItem(placement: .bottomOrnament) {
                Button("Fechar", systemImage: "xmark") { dismissWindow() }
            }
        }
        .task(id: messageID) {
            do {
                let response: ACARSDetail = try await VisionAPIClient.shared.fetch(
                    "api/acars/message/\(messageID)", query: [URLQueryItem(name: "libacars", value: "0")])
                detail = response.message
                ACARSMessageCache.shared.store([response.message])
                error = nil
            } catch { self.error = error.localizedDescription }
        }
    }

    private func field(_ name: String, _ value: String) -> some View {
        HStack {
            Text(name).foregroundStyle(.secondary)
            Spacer()
            Text(value).textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }
}
