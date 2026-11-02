import Accessibility
import Charts
import Foundation
import SwiftUI

/// One cell of a day × hour grid (used by the Chart3D views).
struct HourDayCell: Identifiable, Hashable, Codable, Sendable {
    /// 0-based day index, oldest first.
    let day: Int
    let dayLabel: String
    /// Hour of day, 0...23.
    let hour: Int
    let value: Double

    var id: String { "\(day)-\(hour)" }
}

/// Pure binning helpers for the day × hour charts (Analytics CPU, ACARS 7d × 24h).
enum HourDayBinning {
    /// Parses the timestamp formats the MeuLab API emits (ISO8601 with/without
    /// zone or fractional seconds, or "yyyy-MM-dd HH:mm[:ss]"). Zone-less values
    /// are read in `timeZone`.
    static func parseTimestamp(_ raw: String, timeZone: TimeZone = .current) -> Date? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: text) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: text) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }

    /// Averages samples into (day, hour) bins. Days are indexed from the oldest
    /// sample's day; empty bins are omitted.
    static func hourDayAverages(_ samples: [(timestamp: String, value: Double)],
                                calendar: Calendar = .current) -> [HourDayCell] {
        var sums: [Date: [Int: (total: Double, count: Int)]] = [:]
        for sample in samples {
            guard let date = parseTimestamp(sample.timestamp, timeZone: calendar.timeZone) else { continue }
            let day = calendar.startOfDay(for: date)
            let hour = calendar.component(.hour, from: date)
            let current = sums[day, default: [:]][hour] ?? (0, 0)
            sums[day, default: [:]][hour] = (current.total + sample.value, current.count + 1)
        }
        let labelFormatter = DateFormatter()
        labelFormatter.locale = Locale(identifier: "pt_BR")
        labelFormatter.timeZone = calendar.timeZone
        labelFormatter.dateFormat = "dd/MM"
        var cells: [HourDayCell] = []
        for (index, day) in sums.keys.sorted().enumerated() {
            let label = labelFormatter.string(from: day)
            for (hour, bin) in sums[day, default: [:]].sorted(by: { $0.key < $1.key }) {
                cells.append(HourDayCell(day: index, dayLabel: label, hour: hour, value: bin.total / Double(bin.count)))
            }
        }
        return cells
    }

    /// Extracts the hour from labels like "14", "14:00", "2026-10-30 14:00" or ISO8601.
    static func parseHour(_ raw: String) -> Int? {
        var text = raw.trimmingCharacters(in: .whitespaces)
        if let separator = text.lastIndex(where: { $0 == "T" || $0 == " " }) {
            text = String(text[text.index(after: separator)...])
        }
        let head = text.split(separator: ":", maxSplits: 1).first.map(String.init) ?? text
        guard let hour = Int(head), (0...23).contains(hour) else { return nil }
        return hour
    }

    /// ACARS has daily totals (7d) and a 24h hourly profile but no 7 × 24 matrix,
    /// so each day's total is spread over the hours using the 24h profile share.
    static func distribute(dailyTotals: [(label: String, total: Int)],
                           hourlyProfile: [(hour: String, count: Int)]) -> [HourDayCell] {
        var profile = [Double](repeating: 0, count: 24)
        for entry in hourlyProfile {
            guard let hour = parseHour(entry.hour) else { continue }
            profile[hour] += Double(entry.count)
        }
        let profileTotal = profile.reduce(0, +)
        guard profileTotal > 0 else { return [] }
        var cells: [HourDayCell] = []
        for (index, day) in dailyTotals.enumerated() {
            for hour in 0..<24 where profile[hour] > 0 {
                cells.append(HourDayCell(day: index, dayLabel: day.label, hour: hour,
                                         value: Double(day.total) * profile[hour] / profileTotal))
            }
        }
        return cells
    }
}

/// VoiceOver / Audio Graph descriptor for a day × hour grid.
struct HourDayChartDescriptor: AXChartDescriptorRepresentable {
    let title: String
    let valueTitle: String
    let unit: String
    let cells: [HourDayCell]

    func makeChartDescriptor() -> AXChartDescriptor {
        var days: [String] = []
        for cell in cells where !days.contains(cell.dayLabel) { days.append(cell.dayLabel) }
        let values = cells.map(\.value)
        let maximum = max(values.max() ?? 1, 1)
        let unit = self.unit
        let xAxis = AXCategoricalDataAxisDescriptor(title: "Dia", categoryOrder: days)
        let yAxis = AXNumericDataAxisDescriptor(title: valueTitle, range: 0...maximum, gridlinePositions: []) {
            "\($0.formatted(.number.precision(.fractionLength(0...1))))\(unit)"
        }
        let hourAxis = AXNumericDataAxisDescriptor(title: "Hora", range: 0...23, gridlinePositions: []) { "\(Int($0)) h" }
        let series = AXDataSeriesDescriptor(name: valueTitle, isContinuous: false, dataPoints: cells.map {
            AXDataPoint(x: $0.dayLabel, y: $0.value, additionalValues: [.number(Double($0.hour))],
                        label: "\($0.dayLabel) às \($0.hour) h")
        })
        let peak = cells.max(by: { $0.value < $1.value })
        let summary = peak.map {
            "\(cells.count) células em \(days.count) dias. Pico \($0.value.formatted(.number.precision(.fractionLength(0...1))))\(unit) em \($0.dayLabel) às \($0.hour) h."
        } ?? "Sem dados."
        return AXChartDescriptor(title: title, summary: summary, xAxis: xAxis, yAxis: yAxis,
                                 additionalAxes: [hourAxis], series: [series])
    }

    func updateChartDescriptor(_ descriptor: AXChartDescriptor) {}
}

/// Descriptor for a simple categorical bar chart.
struct BarChartDescriptor: AXChartDescriptorRepresentable {
    let title: String
    let xTitle: String
    let yTitle: String
    let points: [(label: String, value: Double)]

    func makeChartDescriptor() -> AXChartDescriptor {
        let maximum = max(points.map(\.value).max() ?? 1, 1)
        let xAxis = AXCategoricalDataAxisDescriptor(title: xTitle, categoryOrder: points.map(\.label))
        let yAxis = AXNumericDataAxisDescriptor(title: yTitle, range: 0...maximum, gridlinePositions: []) {
            $0.formatted(.number.precision(.fractionLength(0)))
        }
        let series = AXDataSeriesDescriptor(name: yTitle, isContinuous: false,
                                            dataPoints: points.map { AXDataPoint(x: $0.label, y: $0.value) })
        let total = points.reduce(0) { $0 + $1.value }
        return AXChartDescriptor(title: title,
                                 summary: "\(points.count) barras, total \(Int(total)), máximo \(Int(maximum)).",
                                 xAxis: xAxis, yAxis: yAxis, additionalAxes: [], series: [series])
    }

    func updateChartDescriptor(_ descriptor: AXChartDescriptor) {}
}

/// Value of the "hour-day-chart" volume.
struct HourDayChartData: Hashable, Codable, Sendable {
    let cells: [HourDayCell]
    let valueTitle: String
    let unit: String
    let title: String
}

/// Day × hour heatmap for scrolling panels: 3D content isn't clipped by a scroll
/// view and collapses to the window's shallow depth, so 3D lives in its own volume.
struct HourDayHeatmap: View {
    let data: HourDayChartData
    @Environment(\.openWindow) private var openWindow

    private var dayCount: Int { Set(data.cells.map(\.day)).count }

    /// ACARS labels days as "yyyy-MM-dd"; the others are already short.
    private func shortDay(_ label: String) -> String {
        guard let date = Formatters.apiDate.date(from: label) else { return label }
        return date.formatted(.dateTime.day(.twoDigits).month(.twoDigits))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Chart(data.cells) { cell in
                RectangleMark(xStart: .value("Hora", cell.hour), xEnd: .value("Hora", cell.hour + 1),
                              y: .value("Dia", shortDay(cell.dayLabel)), height: .ratio(0.92))
                    .foregroundStyle(by: .value(data.valueTitle, cell.value))
            }
            .chartForegroundStyleScale(range: Gradient(colors: [.indigo, .cyan, .yellow]))
            .chartXScale(domain: 0...24)
            .chartXAxis { AxisMarks(values: .stride(by: 6)) { AxisValueLabel() } }
            .chartYAxis { AxisMarks(preset: .aligned, position: .leading) { AxisValueLabel() } }
            .frame(height: CGFloat(dayCount) * 34 + 56)
            .accessibilityChartDescriptor(HourDayChartDescriptor(title: data.title, valueTitle: data.valueTitle,
                                                                 unit: data.unit, cells: data.cells))
            Button("Ver em 3D", systemImage: "cube") { openWindow(id: "hour-day-chart", value: data) }
        }
    }
}

/// Rotatable 3D scatter of a day × hour grid, shown in the "hour-day-chart" volume.
struct HourDayChart3D: View {
    let data: HourDayChartData
    @State private var pose: Chart3DPose = .default

    var body: some View {
        Chart3D(data.cells) { cell in
            PointMark(x: .value("Dia", cell.day),
                      y: .value(data.valueTitle, cell.value),
                      z: .value("Hora", cell.hour))
                .foregroundStyle(by: .value("Dia", cell.dayLabel))
        }
        .chart3DPose($pose)
        // Axes share one scale by default: values in the hundreds would flatten days and hours into a line.
        .chartXScale(domain: 0...max(data.cells.map(\.day).max() ?? 1, 1), range: -0.5...0.5)
        .chartYScale(domain: 0...max(data.cells.map(\.value).max() ?? 1, 1), range: -0.5...0.5)
        .chartZScale(domain: 0...23, range: -0.5...0.5)
        .chartXAxisLabel("Dia")
        .chartYAxisLabel(data.valueTitle)
        .chartZAxisLabel("Hora")
        // Chart3D doesn't expand to the volume by itself.
        .frame(width: 1_400, height: 1_200)
        .frame(depth: 1_200)
        .accessibilityChartDescriptor(HourDayChartDescriptor(title: data.title, valueTitle: data.valueTitle,
                                                             unit: data.unit, cells: data.cells))
    }
}
