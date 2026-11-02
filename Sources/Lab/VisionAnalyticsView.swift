import Charts
import SwiftUI

private struct VisionChartPoint: Identifiable {
    let id: Int
    let label: String
    let value: Double
}

private enum VisionAnalyticsMetric: String, CaseIterable, Identifiable {
    case cpu = "CPU", memory = "Memória", disk = "Disco", temperature = "Temperatura"
    var id: String { rawValue }
    var color: Color {
        switch self {
        case .cpu: .cyan
        case .memory: .purple
        case .disk: .orange
        case .temperature: .red
        }
    }
    var unit: String { self == .temperature ? "°C" : "%" }
}

struct VisionAnalyticsView: View {
    @State private var period = "24h"
    @State private var metric: VisionAnalyticsMetric = .cpu
    @State private var system: VisionSystemAnalytics?
    @State private var adsb: VisionADSBAnalytics?
    @State private var systemError: String?
    @State private var adsbError: String?
    @State private var loading = false
    @State private var updatedAt: Date?
    @State private var refreshID = UUID()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Label("Analytics", systemImage: "chart.xyaxis.line").font(.largeTitle.bold())
                    Spacer()
                    if loading { ProgressView() }
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text("Sistema · dados do servidor · \(metric.rawValue)").font(.title2.bold())
                    if let system {
                        let points = points(for: metric, in: system)
                        if points.isEmpty {
                            empty("Sem amostras de \(metric.rawValue.lowercased()) nesse período.")
                        } else {
                            HStack(spacing: 14) {
                                stat("Média", average(for: metric, in: system), unit: metric.unit)
                                stat("Pico", peak(for: metric, in: system), unit: metric.unit)
                                stat("Amostras", Double(points.count), unit: "")
                            }
                            Chart(points) { point in
                                AreaMark(x: .value("Amostra", point.id), y: .value(metric.rawValue, point.value))
                                    .foregroundStyle(metric.color.opacity(0.16))
                                LineMark(x: .value("Amostra", point.id), y: .value(metric.rawValue, point.value))
                                    .foregroundStyle(metric.color)
                                    .interpolationMethod(.catmullRom)
                            }
                            .chartXAxis(.hidden)
                            .frame(height: 195)
                            .accessibilityChartDescriptor(LineChartDescriptor(
                                title: "\(metric.rawValue) no período", xTitle: "Amostra", yTitle: metric.rawValue,
                                unit: metric.unit, points: points.map { ($0.label, $0.value) }))
                            HStack {
                                Text(points.first?.label ?? "")
                                Spacer()
                                Text(points.last?.label ?? "")
                            }
                            .font(.caption).foregroundStyle(.secondary)
                        }
                        if let uptime = system.uptime {
                            HStack(spacing: 14) {
                                stat("Uptime atual", Double(uptime.current) / 86_400, unit: " dias")
                                stat("Uptime médio", Double(uptime.average) / 86_400, unit: " dias")
                                stat("Reinícios", Double(uptime.reboots), unit: "")
                            }
                        }
                        HStack(spacing: 14) {
                            if let minimum = system.cpu.minimum { stat("CPU mínima", minimum, unit: "%") }
                            if let minimum = system.memory.minimumAvailable { stat("RAM livre mínima", minimum / 1_024, unit: " GB") }
                            if let growth = system.disk.growthRate { stat("Crescimento disco", growth, unit: " GB/dia") }
                        }
                    } else if let systemError {
                        empty(systemError)
                    } else { ProgressView("Carregando sistema…") }
                }
                .padding(20)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 20))

                if let system {
                    cpuHourDayPanel(system)
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text("Tráfego ADS-B · histórico do receptor").font(.title2.bold())
                    if let adsb {
                        HStack(spacing: 14) {
                            stat("Observações", Double(adsb.totalFlights), unit: "")
                            stat("Aeronaves únicas", Double(adsb.uniqueAircraft), unit: "")
                        }
                        if adsb.hourlyStats.isEmpty {
                            empty("Sem histórico ADS-B nesse período.")
                        } else {
                            Chart(adsb.hourlyStats, id: \.hour) { hour in
                                BarMark(x: .value("Hora", hour.hour), y: .value("Observações", hour.flightCount))
                                    .foregroundStyle(.cyan.gradient)
                            }
                            .frame(height: 165)
                            .accessibilityChartDescriptor(BarChartDescriptor(
                                title: "Observações ADS-B por hora", xTitle: "Hora", yTitle: "Observações",
                                points: adsb.hourlyStats.map { ("\($0.hour) h", Double($0.flightCount)) }))
                        }
                        if let daily = adsb.dailyStats, !daily.isEmpty {
                            Text("Por dia").font(.headline)
                            Chart(daily, id: \.date) { day in
                                BarMark(x: .value("Dia", day.date), y: .value("Observações", day.flightCount))
                                    .foregroundStyle(.blue.gradient)
                            }
                            .frame(height: 165)
                            .accessibilityChartDescriptor(BarChartDescriptor(
                                title: "Observações ADS-B por dia", xTitle: "Dia", yTitle: "Observações",
                                points: daily.map { ($0.date, Double($0.flightCount)) }))
                            ForEach(daily, id: \.date) { day in
                                HStack {
                                    Text(day.date)
                                    Spacer()
                                    Text("\(day.flightCount) observações · \(day.uniqueAircraft) aeronaves")
                                        .foregroundStyle(.secondary)
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                        analyticsList("Tipos de aeronave", items: (adsb.topAircraftTypes ?? []).map { ("\($0.type) · \($0.count)", $0.percentage) })
                        analyticsList("Rotas", items: (adsb.topRoutes ?? []).map { ("\($0.origin) → \($0.destination) · \($0.count)", $0.percentage) })
                        analyticsList("Faixas de altitude", items: (adsb.altitudeDistribution ?? []).map { ("\($0.range) · \($0.count)", $0.percentage) })
                    } else if let adsbError {
                        empty(adsbError)
                    } else { ProgressView("Carregando ADS-B…") }
                }
                .padding(20)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 20))
                if let updatedAt {
                    Text("Atualizado \(updatedAt.formatted(date: .omitted, time: .standard)) · MeuLab API")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(28)
        .toolbar {
            ToolbarItemGroup(placement: .bottomOrnament) {
                Picker("Período", selection: $period) {
                    Text("24 horas").tag("24h")
                    Text("7 dias").tag("7d")
                }
                .pickerStyle(.segmented)
                Picker("Métrica", selection: $metric) {
                    ForEach(VisionAnalyticsMetric.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                // Ornament would otherwise squeeze the segments and cut their titles.
                .fixedSize()
                Button("Atualizar", systemImage: "arrow.clockwise") { Task { await refresh() } }
            }
        }
        .task(id: period) { await refresh() }
    }

    /// CPU × hour × day in 3D, binned from the same samples as the 2D chart.
    @ViewBuilder private func cpuHourDayPanel(_ system: VisionSystemAnalytics) -> some View {
        let cells = HourDayBinning.hourDayAverages(system.cpu.dataPoints.map { ($0.timestamp, $0.usage) })
        if !cells.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("CPU por hora e dia").font(.title2.bold())
                Text(Set(cells.map(\.day)).count > 1
                     ? "Média de uso de CPU em cada hora de cada dia."
                     : "Só um dia de amostras; escolha 7 dias para comparar dias.")
                    .font(.callout).foregroundStyle(.secondary)
                HourDayHeatmap(data: HourDayChartData(cells: cells, valueTitle: "CPU", unit: "%", title: "CPU por hora e dia"))
            }
            .padding(20)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 20))
        }
    }

    @ViewBuilder private func empty(_ message: String) -> some View {
        Label(message, systemImage: "info.circle")
            .foregroundStyle(.secondary)
            .padding(12)
    }

    private func analyticsList(_ title: String, items: [(String, Double)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            if items.isEmpty {
                Text("Sem dados registrados neste período.").foregroundStyle(.secondary)
            } else {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack {
                        Text(item.0)
                        Spacer()
                        Text("\(item.1.formatted(.number.precision(.fractionLength(1))))%")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.top, 10)
    }

    private func stat(_ title: String, _ value: Double, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text("\(value.formatted(.number.precision(.fractionLength(unit.isEmpty ? 0 : 1))))\(unit)")
                .font(.title3.bold()).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    private func points(for metric: VisionAnalyticsMetric, in value: VisionSystemAnalytics) -> [VisionChartPoint] {
        let samples: [(String, Double)]
        switch metric {
        case .cpu: samples = value.cpu.dataPoints.map { ($0.timestamp, $0.usage) }
        case .memory: samples = value.memory.dataPoints.map { ($0.timestamp, $0.usedPercent) }
        case .disk: samples = value.disk.dataPoints.map { ($0.timestamp, $0.usedPercent) }
        case .temperature: samples = value.temperature.dataPoints.map { ($0.timestamp, $0.temperature) }
        }
        return samples.enumerated().map { index, sample in
            let label = HourDayBinning.parseTimestamp(sample.0).map(Formatters.dayMonthTime.string(from:))
            return VisionChartPoint(id: index, label: label ?? sample.0, value: sample.1)
        }
    }

    private func average(for metric: VisionAnalyticsMetric, in value: VisionSystemAnalytics) -> Double {
        switch metric {
        case .cpu: value.cpu.average
        case .memory: value.memory.averageUsage
        case .disk: value.disk.averageUsage
        case .temperature: value.temperature.average
        }
    }

    private func peak(for metric: VisionAnalyticsMetric, in value: VisionSystemAnalytics) -> Double {
        switch metric {
        case .cpu: value.cpu.peak
        case .memory: value.memory.peakUsage
        case .disk: value.disk.peakUsage
        case .temperature: value.temperature.peak
        }
    }

    private func refresh() async {
        let id = UUID()
        let selectedPeriod = period
        refreshID = id
        loading = true
        defer {
            if refreshID == id { loading = false; updatedAt = Date() }
        }
        do {
            let api = try VisionAPIClient.shared
            do {
                let result: VisionSystemAnalytics = try await api.fetch("api/analytics/system", query: [
                    URLQueryItem(name: "period", value: selectedPeriod),
                    URLQueryItem(name: "interval", value: "15m")
                ])
                guard refreshID == id, !Task.isCancelled else { return }
                system = result
                systemError = nil
            } catch {
                guard refreshID == id, !Task.isCancelled else { return }
                system = nil
                systemError = error.localizedDescription
            }
            do {
                let result: VisionADSBAnalytics = try await api.fetch("api/analytics/adsb", query: [URLQueryItem(name: "period", value: selectedPeriod)])
                guard refreshID == id, !Task.isCancelled else { return }
                adsb = result
                adsbError = nil
            } catch {
                guard refreshID == id, !Task.isCancelled else { return }
                adsb = nil
                adsbError = error.localizedDescription
            }
        } catch {
            guard refreshID == id, !Task.isCancelled else { return }
            systemError = error.localizedDescription
            adsbError = error.localizedDescription
        }
    }
}
