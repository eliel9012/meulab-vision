import Charts
import SwiftUI

struct VisionSystemExtrasView: View {
    @State private var history: VisionCPUHistory?
    @State private var devices: [FirestickDevice] = []
    @State private var selectedDeviceID = ""
    @State private var firestick: FirestickStatusResponse?
    @State private var historyError: String?
    @State private var firestickError: String?
    @State private var loading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Histórico de CPU", systemImage: "chart.xyaxis.line").font(.title2.bold())
                    Spacer()
                    if loading { ProgressView() }
                    Button("Atualizar", systemImage: "arrow.clockwise") { Task { await refresh() } }
                }
                if let history {
                    HStack(spacing: 18) {
                        value("Média", history.cpu.average)
                        value("Pico", history.cpu.peak)
                        value("Mínimo", history.cpu.minimum)
                    }
                    if history.cpu.dataPoints.isEmpty {
                        Text("Sem amostras de CPU nas últimas 24 horas.").foregroundStyle(.secondary)
                    } else {
                        Chart(Array(history.cpu.dataPoints.enumerated()), id: \.offset) { index, point in
                            AreaMark(x: .value("Amostra", index), y: .value("Uso", point.usage))
                                .foregroundStyle(.cyan.opacity(0.17))
                            LineMark(x: .value("Amostra", index), y: .value("Uso", point.usage))
                                .foregroundStyle(.cyan)
                        }
                        .chartXAxis(.hidden)
                        .frame(height: 180)
                        .accessibilityChartDescriptor(LineChartDescriptor(
                            title: "Histórico de CPU", xTitle: "Horário", yTitle: "Uso de CPU", unit: "%",
                            points: history.cpu.dataPoints.map {
                                (label: $0.timestamp.replacingOccurrences(of: "T", with: " "), value: $0.usage)
                            }))
                        HStack {
                            Text(history.cpu.dataPoints.first?.timestamp.replacingOccurrences(of: "T", with: " ") ?? "")
                            Spacer()
                            Text(history.cpu.dataPoints.last?.timestamp.replacingOccurrences(of: "T", with: " ") ?? "")
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                } else if let historyError {
                    Label(historyError, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                } else { ProgressView("Carregando histórico…") }
            }
            .padding(18)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
            .offset(z: SpatialDepth.card)

            VStack(alignment: .leading, spacing: 14) {
                Label("Fire Stick", systemImage: "tv").font(.title2.bold())
                if !devices.isEmpty {
                    Picker("Dispositivo", selection: $selectedDeviceID) {
                        ForEach(devices) { device in Text(device.name).tag(device.id) }
                    }
                    .onChange(of: selectedDeviceID) { _, _ in Task { await loadFirestickStatus() } }
                }
                if let firestick {
                    let status = firestick.firestick
                    HStack(spacing: 14) {
                        statusTile("TV", status.tvOn.map { $0 ? "Ligada" : "Desligada" } ?? "Indisponível", symbol: "tv")
                        statusTile("Entrada", status.tvShowingFirestick.map { $0 ? "Fire Stick" : "Outra" } ?? "Indisponível", symbol: "cable.connector")
                        statusTile("ADB", status.adb.deviceState ?? "Indisponível", symbol: "network")
                    }
                    if let app = status.foregroundApp {
                        LabeledContent("App em primeiro plano", value: app.package ?? app.component ?? "—")
                    }
                    LabeledContent("Dispositivo", value: "\(status.name) · \(status.ip)")
                    if let error = status.error, !error.isEmpty {
                        Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    }
                } else if let firestickError {
                    Label(firestickError, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                } else if devices.isEmpty {
                    Text("Nenhum Fire Stick cadastrado.").foregroundStyle(.secondary)
                } else { ProgressView("Consultando Fire Stick…") }
            }
            .padding(18)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
            .offset(z: SpatialDepth.card)

            VisionAskLabView(cpuHistory: history)
        }
        .polling(every: .seconds(60)) { await refresh() }
    }

    private func value(_ title: String, _ amount: Double) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text("\(amount.formatted(.number.precision(.fractionLength(1))))%")
                .font(.title3.bold()).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func statusTile(_ title: String, _ status: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
            Text(status).font(.headline).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .depthCard()
    }

    private func refresh() async {
        loading = true
        defer { loading = false }
        do {
            let api = try VisionAPIClient.shared
            do {
                history = try await api.fetch("api/analytics/system?period=24h&interval=5m")
                historyError = nil
            } catch {
                historyError = error.localizedDescription
            }
            do {
                let result: FirestickDevicesResponse = try await api.fetch("api/firestick/devices")
                devices = result.devices
                if !devices.contains(where: { $0.id == selectedDeviceID }) {
                    selectedDeviceID = result.defaultId.flatMap { id in devices.first(where: { $0.id == id })?.id }
                        ?? devices.first?.id ?? ""
                }
                firestickError = nil
                await loadFirestickStatus(api: api)
            } catch {
                firestickError = error.localizedDescription
            }
        } catch {
            historyError = error.localizedDescription
            firestickError = error.localizedDescription
        }
    }

    private func loadFirestickStatus(api existingAPI: VisionAPIClient? = nil) async {
        guard !selectedDeviceID.isEmpty else { firestick = nil; return }
        do {
            let api = try existingAPI ?? VisionAPIClient.shared
            let id = selectedDeviceID
            let result: FirestickStatusResponse = try await api.fetch("api/firestick/status",
                                                                      query: [URLQueryItem(name: "id", value: id)])
            guard id == selectedDeviceID else { return }
            firestick = result
            firestickError = nil
        } catch {
            firestick = nil
            firestickError = error.localizedDescription
        }
    }
}
