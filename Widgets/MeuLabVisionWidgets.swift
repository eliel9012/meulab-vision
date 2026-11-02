import SwiftUI
import WidgetKit

@main
struct MeuLabVisionWidgets: WidgetBundle {
    var body: some Widget {
        SystemWidget()
        AlertsWidget()
        TripWidget()
        RadarWidget()
    }
}

// MARK: - Timeline

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        let snapshot = context.isPreview ? (WidgetSnapshot.load() ?? .placeholder) : WidgetSnapshot.load()
        completion(SnapshotEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let now = Date()
        let snapshot = WidgetSnapshot.load()
        // Entradas horárias mantêm a contagem de dias da viagem certa sem o app aberto.
        let entries = (0..<6).map { hour in
            SnapshotEntry(date: now.addingTimeInterval(TimeInterval(hour) * 3_600), snapshot: snapshot)
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(30 * 60))))
    }
}

// MARK: - Widgets

struct SystemWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "fun.meulab.vision.widget.system", provider: SnapshotProvider()) { entry in
            SystemWidgetView(entry: entry)
        }
        .configurationDisplayName("Sistema")
        .description("CPU, RAM, disco e temperatura do homelab.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular])
        .widgetTexture(.glass)
        .supportedMountingStyles([.elevated, .recessed])
    }
}

struct AlertsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "fun.meulab.vision.widget.alerts", provider: SnapshotProvider()) { entry in
            AlertsWidgetView(entry: entry)
        }
        .configurationDisplayName("Alertas")
        .description("Alertas ainda não reconhecidos.")
        .supportedFamilies([.systemSmall, .accessoryRectangular])
        .widgetTexture(.glass)
        .supportedMountingStyles([.elevated, .recessed])
    }
}

struct TripWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "fun.meulab.vision.widget.trip", provider: SnapshotProvider()) { entry in
            TripWidgetView(entry: entry)
        }
        .configurationDisplayName("Viagem")
        .description("Próximo voo e dias que faltam.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .widgetTexture(.paper)
        .supportedMountingStyles([.elevated, .recessed])
    }
}

struct RadarWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "fun.meulab.vision.widget.radar", provider: SnapshotProvider()) { entry in
            RadarWidgetView(entry: entry)
        }
        .configurationDisplayName("ADS-B")
        .description("Aeronaves recebidas pelo radar.")
        .supportedFamilies([.systemSmall, .accessoryRectangular])
        .widgetTexture(.glass)
        .supportedMountingStyles([.elevated, .recessed])
    }
}

// MARK: - Views

private struct SystemWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.levelOfDetail) private var levelOfDetail

    var body: some View {
        let detail = WidgetDetail(isSimplified: levelOfDetail == .simplified)
        let content = WidgetContent.system(entry.snapshot, detail: detail)
        Group {
            switch family {
            case .accessoryCircular:
                circular(detail: detail)
            default:
                WidgetCard(symbol: "cpu", title: "Sistema", content: content, detail: detail,
                           columns: family == .systemMedium ? 2 : 1,
                           age: WidgetContent.ageLabel(updatedAt: entry.snapshot?.updatedAt, now: entry.date))
            }
        }
        .widgetURL(WidgetDeepLink.system.url)
        .containerBackground(for: .widget) { Color.clear }
    }

    @ViewBuilder
    private func circular(detail: WidgetDetail) -> some View {
        let system = entry.snapshot?.system
        // Longe: só a CPU; perto: gauge de CPU com temperatura no rótulo.
        if detail == .glanceable {
            ZStack {
                AccessoryWidgetBackground()
                Text(WidgetContent.percent(system?.cpuPercent)).font(.title3.bold()).minimumScaleFactor(0.5)
            }
        } else {
            Gauge(value: min(max(system?.cpuPercent ?? 0, 0), 100), in: 0...100) {
                Text("CPU")
            } currentValueLabel: {
                Text(WidgetContent.percent(system?.cpuPercent))
            } minimumValueLabel: {
                Text(WidgetContent.temperature(system?.temperatureC)).font(.system(size: 8))
            } maximumValueLabel: {
                Text("")
            }
            .gaugeStyle(.accessoryCircular)
        }
    }
}

private struct AlertsWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.levelOfDetail) private var levelOfDetail

    var body: some View {
        let detail = WidgetDetail(isSimplified: levelOfDetail == .simplified)
        let content = WidgetContent.alerts(entry.snapshot, detail: detail)
        let age = WidgetContent.ageLabel(updatedAt: entry.snapshot?.updatedAt, now: entry.date)
        Group {
            if family == .accessoryRectangular {
                RectangularRow(symbol: "bell.badge.fill", content: content, detail: detail, age: age)
            } else {
                WidgetCard(symbol: "bell.badge.fill", title: "Alertas", content: content, detail: detail,
                           tint: (entry.snapshot?.alerts?.pendingCount ?? 0) > 0 ? .orange : .green,
                           age: age)
            }
        }
        .widgetURL(WidgetDeepLink.alerts.url)
        .containerBackground(for: .widget) { Color.clear }
    }
}

private struct TripWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.levelOfDetail) private var levelOfDetail

    var body: some View {
        let detail = WidgetDetail(isSimplified: levelOfDetail == .simplified)
        let content = WidgetContent.trip(entry.snapshot, now: entry.date, detail: detail)
        WidgetCard(symbol: "airplane.departure", title: "Viagem", content: content, detail: detail,
                   columns: family == .systemMedium ? 2 : 1)
            .widgetURL(WidgetDeepLink.trip.url)
            .containerBackground(for: .widget) { Color.clear }
    }
}

private struct RadarWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.levelOfDetail) private var levelOfDetail

    var body: some View {
        let detail = WidgetDetail(isSimplified: levelOfDetail == .simplified)
        let content = WidgetContent.radar(entry.snapshot, detail: detail)
        let age = WidgetContent.ageLabel(updatedAt: entry.snapshot?.updatedAt, now: entry.date)
        Group {
            if family == .accessoryRectangular {
                RectangularRow(symbol: "airplane", content: content, detail: detail, age: age)
            } else {
                WidgetCard(symbol: "airplane", title: "ADS-B", content: content, detail: detail, age: age)
            }
        }
        .widgetURL(WidgetDeepLink.radar.url)
        .containerBackground(for: .widget) { Color.clear }
    }
}

// MARK: - Building blocks

private struct WidgetCard: View {
    let symbol: String
    let title: String
    let content: WidgetContent
    let detail: WidgetDetail
    var tint: Color = .accentColor
    var columns = 1
    var age: String?

    var body: some View {
        if detail == .glanceable {
            // Longe: um número grande, legível do outro lado da sala.
            VStack(spacing: 4) {
                Text(content.headline)
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                Label(content.caption, systemImage: symbol)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(title, systemImage: symbol)
                        .font(.caption.bold())
                        .foregroundStyle(tint)
                    Text(content.headline)
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text(content.caption).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    if let age {
                        Label(age, systemImage: "clock").font(.caption2).foregroundStyle(.orange).lineLimit(1)
                    }
                    if columns == 1 { lines }
                    Spacer(minLength: 0)
                }
                if columns > 1 {
                    VStack(alignment: .leading, spacing: 6) { lines }
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var lines: some View {
        ForEach(content.lines, id: \.self) { line in
            Text(line).font(.footnote.monospacedDigit()).lineLimit(1)
        }
    }
}

private struct RectangularRow: View {
    let symbol: String
    let content: WidgetContent
    let detail: WidgetDetail
    var age: String?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.title3)
            VStack(alignment: .leading, spacing: 0) {
                Text(content.headline).font(.title2.bold()).lineLimit(1)
                Text(content.caption).font(.caption).lineLimit(1)
                if detail == .detailed, let line = age ?? content.lines.first {
                    Text(line).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }
}
