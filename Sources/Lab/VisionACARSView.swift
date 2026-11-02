import Charts
import SwiftUI

struct VisionACARSView: View {
    @State private var summary: ACARSDashboard?
    @State private var hourly: [ACARSHourly.Hour] = []
    @State private var history: ACARSHistory?
    @State private var messages: [ACARSItem] = []
    @State private var results: [ACARSItem]?
    @State private var query = ""
    @Environment(\.pushWindow) private var pushWindow
    @State private var error: String?
    @State private var searchError: String?
    @State private var loading = false
    @State private var searching = false
    @State private var updatedAt: Date?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Label("ACARS", systemImage: "waveform.path").font(.largeTitle.bold())
                    Spacer()
                    if loading { ProgressView() }
                }
                if let error { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                if let summary {
                    HStack(spacing: 14) {
                        metric("Mensagens hoje", summary.today.messages)
                        metric("Última hora", summary.lastHour)
                        metric("Voos", summary.today.flights)
                        metric("Aeronaves", summary.today.aircraft)
                    }
                    Text("Últimas 24 h: \(summary.last24h.messages) mensagens · pico \(summary.today.peakHour ?? "—")")
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 18) {
                    chartPanel("Mensagens por hora") {
                        if hourly.isEmpty { empty("Sem amostras por hora.") }
                        else {
                            Chart(hourly) { hour in
                                BarMark(x: .value("Hora", hour.hour), y: .value("Mensagens", hour.messages))
                                    .foregroundStyle(.cyan.gradient)
                            }
                            .chartXAxis(.hidden)
                            .frame(height: 180)
                            .accessibilityChartDescriptor(BarChartDescriptor(
                                title: "Mensagens ACARS por hora", xTitle: "Hora", yTitle: "Mensagens",
                                points: hourly.map { ($0.hour, Double($0.messages)) }))
                        }
                    }
                    chartPanel("Últimos 7 dias") {
                        if let days = history?.last7Days, !days.isEmpty {
                            Chart(days) { day in
                                BarMark(x: .value("Dia", day.day), y: .value("Mensagens", day.messages))
                                    .foregroundStyle(.purple.gradient)
                            }
                            .chartXAxis(.hidden)
                            .frame(height: 180)
                            .accessibilityChartDescriptor(BarChartDescriptor(
                                title: "Mensagens ACARS nos últimos 7 dias", xTitle: "Dia", yTitle: "Mensagens",
                                points: days.map { ($0.day, Double($0.messages)) }))
                        } else { empty("Sem histórico diário.") }
                    }
                }
                let weekCells = weekMatrix
                if !weekCells.isEmpty {
                    panel("Mensagens 7 dias × 24 h") {
                        Text("Estimativa: total de cada dia distribuído pelo perfil horário das últimas 24 h.")
                            .font(.callout).foregroundStyle(.secondary)
                        HourDayHeatmap(data: HourDayChartData(cells: weekCells, valueTitle: "Mensagens", unit: "",
                                                              title: "Mensagens ACARS estimadas por dia e hora"))
                    }
                }
                if let summary {
                    HStack(alignment: .top, spacing: 18) {
                        panel("Aeronaves mais recebidas") {
                            ForEach(summary.topAircraft) { aircraft in
                                Button {
                                    query = aircraft.tail
                                    Task { await search() }
                                } label: {
                                    HStack {
                                        Text(aircraft.tail).font(.headline)
                                        Text(aircraft.flight ?? "").foregroundStyle(.secondary)
                                        Spacer()
                                        Text("\(aircraft.count) msgs").monospacedDigit()
                                    }
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 8)
                                }
                                .buttonStyle(.plain)
                                .liftCard(cornerRadius: 10)
                            }
                        }
                        panel("Tipos de mensagem") {
                            ForEach(summary.topLabels) { label in
                                HStack {
                                    Text(label.label).font(.headline.monospaced())
                                    Text(label.description ?? "").foregroundStyle(.secondary)
                                    Spacer()
                                    Text("\(label.count)").monospacedDigit()
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                }
                panel("Buscar mensagens") {
                    HStack {
                        TextField("Voo, matrícula ou texto", text: $query)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { Task { await search() } }
                        Button("Buscar", systemImage: "magnifyingglass") { Task { await search() } }
                            .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || searching)
                        if results != nil { Button("Limpar") { results = nil; query = "" } }
                    }
                    if searching { ProgressView("Buscando…") }
                    if let searchError { Text(searchError).foregroundStyle(.orange) }
                    let visible = results ?? messages
                    if visible.isEmpty { empty(results == nil ? "Nenhuma mensagem recente." : "Nenhuma mensagem encontrada.") }
                    ForEach(visible) { item in
                        Button { pushWindow(id: "acars-message", value: item.id) } label: { messageRow(item) }
                            .buttonStyle(.plain)
                            .liftCard(cornerRadius: 12)
                            .accessibilityHint("Abre a mensagem completa")
                    }
                }
                if let updatedAt { Text("Atualizado \(updatedAt.formatted(date: .omitted, time: .standard)) · MeuLab API")
                    .font(.caption).foregroundStyle(.secondary) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(28)
        }
        .scrollInputBehavior(.enabled, for: .look)
        .toolbar {
            ToolbarItemGroup(placement: .bottomOrnament) {
                if results != nil {
                    Button("Limpar busca", systemImage: "xmark.circle") { results = nil; query = "" }
                }
                Button("Atualizar", systemImage: "arrow.clockwise") { Task { await refresh() } }
            }
        }
        .polling(every: .seconds(30)) { await refresh() }
    }

    /// 7 days × 24 h derived from daily totals and the 24 h hourly profile.
    private var weekMatrix: [HourDayCell] {
        guard let history, !history.last7Days.isEmpty else { return [] }
        let profile = history.last24hHours.isEmpty
            ? hourly.map { (hour: $0.hour, count: $0.messages) }
            : history.last24hHours.map { (hour: $0.hour, count: $0.messages) }
        return HourDayBinning.distribute(dailyTotals: history.last7Days.map { (label: $0.day, total: $0.messages) },
                                         hourlyProfile: profile)
    }

    private func refresh() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let api = try VisionAPIClient.shared
            async let s: ACARSDashboard = api.fetch("api/acars/summary")
            async let h: ACARSHourly = api.fetch("api/acars/hourly")
            async let d: ACARSHistory = api.fetch("api/acars/history")
            async let m: ACARSList = api.fetch("api/acars/messages?limit=50&details=1&libacars=0")
            let (newSummary, newHours, newHistory, newMessages) = try await (s, h, d, m)
            guard !Task.isCancelled else { return }
            summary = newSummary
            hourly = newHours.hours
            history = newHistory
            messages = newMessages.messages
            ACARSMessageCache.shared.store(newMessages.messages)
            updatedAt = Date()
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func search() async {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }
        searching = true
        defer { searching = false }
        do {
            let response: ACARSSearch = try await VisionAPIClient.shared.fetch("api/acars/search", query: [
                URLQueryItem(name: "q", value: term),
                URLQueryItem(name: "details", value: "1"),
                URLQueryItem(name: "libacars", value: "0")
            ])
            guard !Task.isCancelled else { return }
            results = response.messages
            ACARSMessageCache.shared.store(response.messages)
            searchError = nil
        } catch { searchError = error.localizedDescription }
    }

    private func metric(_ title: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text("\(value)").font(.title.bold()).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }

    private func chartPanel<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        panel(title, content: content)
    }

    private func panel<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(title).font(.title2.bold())
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
    }

    private func empty(_ text: String) -> some View { Text(text).foregroundStyle(.secondary).padding(12) }

    private func messageRow(_ item: ACARSItem) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "envelope.badge").foregroundStyle(.cyan)
                .accessibilityLabel("Mensagem ACARS")
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.title).font(.headline)
                    Text(item.label ?? "—").font(.caption.monospaced()).foregroundStyle(.cyan)
                    Spacer()
                    Text(item.time).font(.caption).foregroundStyle(.secondary)
                }
                if let route = item.route { Text(route).font(.caption).foregroundStyle(.secondary) }
                Text(item.text ?? item.labelDesc ?? "Sem texto decodificado")
                    .font(.callout).lineLimit(2).foregroundStyle(.secondary)
            }
        }
        .padding(13)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }
}
