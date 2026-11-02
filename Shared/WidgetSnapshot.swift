import Foundation

/// Snapshot compartilhado entre o app e a extensão de widgets (App Group).
/// Compilado nos dois targets: manter sem dependências de tipos do app.
struct WidgetSnapshot: Codable, Equatable, Sendable {
    struct System: Codable, Equatable, Sendable {
        var hostname: String?
        var cpuPercent: Double?
        var memoryPercent: Double?
        var diskPercent: Double?
        var temperatureC: Double?
    }

    struct Alerts: Codable, Equatable, Sendable {
        var pendingCount: Int
        var latestMessage: String?
    }

    struct Radar: Codable, Equatable, Sendable {
        var aircraftCount: Int
        var positionedCount: Int
    }

    struct TripFlight: Codable, Equatable, Sendable, Identifiable {
        var id: String
        var code: String
        var originCode: String
        var destinationCode: String
        var departure: Date
        var route: String { "\(originCode) → \(destinationCode)" }
    }

    var system: System?
    var alerts: Alerts?
    var radar: Radar?
    /// Próximos voos em ordem; a extensão escolhe o primeiro ainda não decolado.
    var tripFlights: [TripFlight] = []
    var updatedAt: Date

    static let appGroup = "group.fun.meulab.vision"
    static let defaultsKey = "widget.snapshot.v1"

    static var sharedDefaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    static func load(from defaults: UserDefaults? = sharedDefaults) -> WidgetSnapshot? {
        guard let data = defaults?.data(forKey: defaultsKey) else { return nil }
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    func save(to defaults: UserDefaults? = WidgetSnapshot.sharedDefaults) {
        guard let data = try? Self.encoder.encode(self) else { return }
        defaults?.set(data, forKey: Self.defaultsKey)
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()

    /// Primeiro voo que ainda não partiu (tolerância de 1 h após a decolagem).
    func nextFlight(after now: Date) -> TripFlight? {
        tripFlights.sorted { $0.departure < $1.departure }
            .first { $0.departure.addingTimeInterval(3_600) >= now }
    }

    static let placeholder = WidgetSnapshot(
        system: .init(hostname: "radar", cpuPercent: 23, memoryPercent: 48, diskPercent: 61, temperatureC: 52),
        alerts: .init(pendingCount: 2, latestMessage: "CPU acima de 80%"),
        radar: .init(aircraftCount: 37, positionedCount: 31),
        tripFlights: [.init(id: "placeholder", code: "UX 9158", originCode: "GRU", destinationCode: "MAD",
                            departure: Date().addingTimeInterval(86_400 * 12))],
        updatedAt: Date())
}

/// Seções abertas pelo toque do widget (`meulabvision://section/<id>`); id = nome do case de `VisionSection`.
enum WidgetDeepLink: String, CaseIterable, Sendable {
    case radar, system, alerts, trip

    static let scheme = "meulabvision"

    var url: URL { URL(string: "\(Self.scheme)://section/\(rawValue)")! }
}

/// Nível de detalhe do widget: perto = detalhe, longe = um número grande.
enum WidgetDetail: Equatable, Sendable {
    case detailed, glanceable

    init(isSimplified: Bool) { self = isSimplified ? .glanceable : .detailed }
}

/// Conteúdo textual de cada widget, independente de SwiftUI (testável).
struct WidgetContent: Equatable, Sendable {
    var headline: String
    var caption: String
    var lines: [String]

    /// O widget repete o snapshot por horas: avisa quando o dado envelheceu (`nil` = recente).
    static func ageLabel(updatedAt: Date?, now: Date) -> String? {
        guard let updatedAt else { return nil }
        let minutes = Int(now.timeIntervalSince(updatedAt) / 60)
        guard minutes >= 15 else { return nil }
        return minutes < 60 ? "há \(minutes) min" : "há \(minutes / 60) h"
    }

    static func percent(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int(value.rounded()))%"
    }

    static func temperature(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int(value.rounded()))°C"
    }

    static func system(_ snapshot: WidgetSnapshot?, detail: WidgetDetail) -> WidgetContent {
        let system = snapshot?.system
        let headline = percent(system?.cpuPercent)
        guard detail == .detailed else { return .init(headline: headline, caption: "CPU", lines: []) }
        return .init(headline: headline, caption: system?.hostname ?? "Sistema", lines: [
            "CPU \(percent(system?.cpuPercent))",
            "RAM \(percent(system?.memoryPercent))",
            "Disco \(percent(system?.diskPercent))",
            "Temp \(temperature(system?.temperatureC))"
        ])
    }

    static func alerts(_ snapshot: WidgetSnapshot?, detail: WidgetDetail) -> WidgetContent {
        let count = snapshot?.alerts?.pendingCount
        let headline = count.map(String.init) ?? "—"
        let caption = count == 1 ? "alerta pendente" : "alertas pendentes"
        guard detail == .detailed else { return .init(headline: headline, caption: "Alertas", lines: []) }
        let latest = snapshot?.alerts?.latestMessage
        let lines = count == 0 ? ["Tudo reconhecido"] : latest.map { [$0] } ?? []
        return .init(headline: headline, caption: caption, lines: lines)
    }

    static func radar(_ snapshot: WidgetSnapshot?, detail: WidgetDetail) -> WidgetContent {
        let radar = snapshot?.radar
        let headline = radar.map { String($0.aircraftCount) } ?? "—"
        guard detail == .detailed else { return .init(headline: headline, caption: "Aeronaves", lines: []) }
        return .init(headline: headline, caption: "aeronaves no radar",
                     lines: radar.map { ["\($0.positionedCount) com posição"] } ?? [])
    }

    static func trip(_ snapshot: WidgetSnapshot?, now: Date, detail: WidgetDetail,
                     calendar: Calendar = .current) -> WidgetContent {
        guard let flight = snapshot?.nextFlight(after: now) else {
            return .init(headline: "—", caption: "Sem voos", lines: [])
        }
        let days = daysUntil(flight.departure, from: now, calendar: calendar)
        let headline = days <= 0 ? "Hoje" : "\(days)d"
        guard detail == .detailed else { return .init(headline: headline, caption: flight.code, lines: []) }
        let caption = days <= 0 ? "voo hoje" : days == 1 ? "falta 1 dia" : "faltam \(days) dias"
        return .init(headline: headline, caption: caption, lines: [flight.code, flight.route])
    }

    /// Dias de calendário entre `now` e a partida (0 = hoje; nunca negativo).
    static func daysUntil(_ date: Date, from now: Date, calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: now)
        let end = calendar.startOfDay(for: date)
        return max(0, calendar.dateComponents([.day], from: start, to: end).day ?? 0)
    }
}

/// Limita `WidgetCenter.reloadAllTimelines()` a uma chamada por intervalo.
struct WidgetReloadThrottle: Sendable {
    var minimumInterval: TimeInterval
    private(set) var lastReload: Date?

    init(minimumInterval: TimeInterval = 60) { self.minimumInterval = minimumInterval }

    /// `true` (e registra o horário) se já passou o intervalo desde o último reload.
    mutating func shouldReload(at now: Date) -> Bool {
        if let lastReload, now.timeIntervalSince(lastReload) < minimumInterval { return false }
        lastReload = now
        return true
    }

    /// Segundos até o próximo reload permitido.
    func remaining(at now: Date) -> TimeInterval {
        guard let lastReload else { return 0 }
        return max(0, minimumInterval - now.timeIntervalSince(lastReload))
    }
}
