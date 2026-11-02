import Foundation

struct VisionTripDay: Decodable, Identifiable {
    let id: String
    let date: String
    let weekday: String
    let title: String
    let tone: String
    let events: [VisionTripEvent]
    /// Ano resolvido a partir do roteiro (`VisionTripCalendar.resolveYears`); não vem do JSON.
    var year: Int?

    private enum CodingKeys: String, CodingKey { case id, date, weekday, title, tone, events }

    var displayDate: String { "\(date) · \(weekday)" }

    /// Ano explícito ou inferido só por este dia (dia da semana).
    var resolvedYear: Int? {
        year ?? VisionTripCalendar.dayMonth(date).flatMap { parsed in
            VisionTripCalendar.weekday(weekday).flatMap { VisionTripCalendar.baseYear(for: [(parsed.day, parsed.month, $0)]) }
        }
    }
}

/// Datas do roteiro vêm como `"22 out"` + `"quinta-feira"`, sem ano.
/// O ano é deduzido do dia da semana (o mais próximo do ano de referência que casa com todos os dias),
/// com virada dez→jan incrementando o ano.
enum VisionTripCalendar {
    static let months: [String: Int] = [
        "jan": 1, "fev": 2, "mar": 3, "abr": 4, "mai": 5, "jun": 6,
        "jul": 7, "ago": 8, "set": 9, "out": 10, "nov": 11, "dez": 12
    ]

    static func dayMonth(_ raw: String) -> (day: Int, month: Int)? {
        let parts = raw.split(separator: " ")
        guard parts.count >= 2, let day = Int(parts[0]),
              let month = months[String(parts[1].prefix(3)).lowercased()],
              (1...31).contains(day) else { return nil }
        return (day, month)
    }

    /// Gregorian weekday (1 = domingo … 7 = sábado).
    static func weekday(_ raw: String) -> Int? {
        let key = raw.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).prefix(3)
        return ["dom": 1, "seg": 2, "ter": 3, "qua": 4, "qui": 5, "sex": 6, "sab": 7][String(key)]
    }

    private static let gregorian: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// Melhor ano-base para a sequência (day, month, weekday): maior nº de dias que casam,
    /// desempate pelo mais próximo de `referenceYear`.
    static func baseYear(for entries: [(day: Int, month: Int, weekday: Int)],
                         referenceYear: Int = Calendar(identifier: .gregorian).component(.year, from: .now),
                         window: Int = 8) -> Int? {
        guard !entries.isEmpty else { return nil }
        let candidates = (referenceYear - window)...(referenceYear + window)
        let scored = candidates.map { base -> (year: Int, hits: Int) in
            let years = rolledYears(months: entries.map(\.month), base: base)
            let hits = zip(entries, years).filter { entry, year in
                guard let date = gregorian.date(from: DateComponents(year: year, month: entry.month, day: entry.day))
                else { return false }
                return gregorian.component(.weekday, from: date) == entry.weekday
            }.count
            return (base, hits)
        }
        guard let best = scored.max(by: { a, b in
            a.hits != b.hits ? a.hits < b.hits : abs(a.year - referenceYear) > abs(b.year - referenceYear)
        }), best.hits > 0 else { return nil }
        return best.year
    }

    /// Ano de cada mês da sequência a partir de `base`, somando 1 quando o mês "volta" (dez → jan).
    static func rolledYears(months: [Int], base: Int) -> [Int] {
        var year = base
        var previous = months.first ?? 1
        return months.map { month in
            if month < previous { year += 1 }
            previous = month
            return year
        }
    }

    /// Preenche `year` de cada dia (dias fora de ordem cronológica são ordenados só para inferir).
    static func resolveYears(_ days: [VisionTripDay],
                             referenceYear: Int = Calendar(identifier: .gregorian).component(.year, from: .now)) -> [VisionTripDay] {
        let parsed = days.enumerated().compactMap { index, day -> (index: Int, day: Int, month: Int, weekday: Int?)? in
            guard let dm = dayMonth(day.date) else { return nil }
            return (index, dm.day, dm.month, weekday(day.weekday))
        }
        // Ordem do arquivo é cronológica; fixtures podem vir invertidas — ordena por (mês, dia) apenas
        // quando não há virada de ano evidente (sequência decrescente curta).
        let ordered = isChronological(parsed.map { ($0.month, $0.day) }) ? parsed
            : parsed.sorted { ($0.month, $0.day) < ($1.month, $1.day) }
        let entries = ordered.compactMap { item in item.weekday.map { (item.day, item.month, $0) } }
        guard let base = baseYear(for: entries, referenceYear: referenceYear) else { return days }
        let years = rolledYears(months: ordered.map(\.month), base: base)
        var result = days
        for (item, year) in zip(ordered, years) where result[item.index].year == nil {
            result[item.index].year = year
        }
        return result
    }

    /// Cronológico = no máximo uma "volta" de mês e só de dez→jan (fim → início de ano).
    private static func isChronological(_ items: [(month: Int, day: Int)]) -> Bool {
        zip(items, items.dropFirst()).allSatisfy { a, b in
            (a.month, a.day) <= (b.month, b.day) || (a.month == 12 && b.month == 1)
        }
    }

    /// Ex.: "22 de outubro – 4 de novembro de 2026".
    static func rangeLabel(_ days: [VisionTripDay]) -> String? {
        let dates = days.compactMap { day -> Date? in
            guard let year = day.year ?? day.resolvedYear, let dm = dayMonth(day.date) else { return nil }
            return gregorian.date(from: DateComponents(year: year, month: dm.month, day: dm.day))
        }
        guard let first = dates.min(), let last = dates.max() else { return nil }
        let locale = Locale(identifier: "pt_BR")
        let dayMonthStyle = Date.FormatStyle(date: .long, time: .omitted, locale: locale, calendar: gregorian,
                                             timeZone: gregorian.timeZone)
        let short = Date.FormatStyle(locale: locale, calendar: gregorian, timeZone: gregorian.timeZone)
            .day().month(.wide)
        let sameYear = gregorian.component(.year, from: first) == gregorian.component(.year, from: last)
        return "\((sameYear ? short : dayMonthStyle).format(first)) – \(dayMonthStyle.format(last))"
    }
}

struct VisionTripEvent: Decodable, Identifiable {
    let id: String
    let time: String
    let icon: String
    let title: String
    let desc: String
    let address: String?
    let lat: Double?
    let lon: Double?
    let tz: String?
    let pending: Bool

    func date(day: VisionTripDay) -> Date? {
        guard let (dayNumber, month) = VisionTripCalendar.dayMonth(day.date),
              let year = day.resolvedYear,
              let match = time.firstMatch(of: /(\d{1,2}):(\d{2})/),
              let hour = Int(match.1), let minute = Int(match.2),
              let zone = TimeZone(identifier: tz ?? "America/Sao_Paulo") else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(from: DateComponents(year: year, month: month, day: dayNumber,
                                                  hour: hour, minute: minute))
    }
}

struct VisionTripFlight: Identifiable {
    let event: VisionTripEvent
    let day: VisionTripDay
    let displayCode: String
    let ident: String
    let originCode: String
    let destinationCode: String
    let departure: Date

    var id: String { event.id }
    var route: String { "\(originCode) → \(destinationCode)" }

    var plannedArrival: Date? {
        guard let match = event.desc.firstMatch(of: /(\d{1,2}):(\d{2})/),
              let hour = Int(match.1), let minute = Int(match.2),
              let zone = VisionTripAirport.known[destinationCode]?.timeZone else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        var parts = calendar.dateComponents([.year, .month, .day], from: departure)
        if let date = event.desc.firstMatch(of: /(\d{1,2})\/(\d{1,2})/),
           let day = Int(date.1), let month = Int(date.2) {
            parts.day = day
            parts.month = month
        }
        parts.hour = hour
        parts.minute = minute
        guard var arrival = calendar.date(from: parts) else { return nil }
        if arrival <= departure { arrival = calendar.date(byAdding: .day, value: 1, to: arrival) ?? arrival }
        return arrival
    }

    static func flights(in days: [VisionTripDay]) -> [Self] {
        VisionTripCalendar.resolveYears(days).flatMap { day in
            day.events.compactMap { event -> Self? in
                guard event.title.hasPrefix("Voo "), !event.pending,
                      let departure = event.date(day: day),
                      let code = event.title.firstMatch(of: /\b([A-Z][A-Z0-9])\s*(\d{2,4})\b/),
                      let route = event.title.firstMatch(of: /\(([A-Z]{3})\).*→.*\(([A-Z]{3})\)/)
                else { return nil }
                let airline = String(code.1)
                let number = String(code.2)
                let stripped = String(number.drop(while: { $0 == "0" }))
                return .init(event: event, day: day,
                             displayCode: "\(airline) \(number)",
                             ident: airline + (stripped.isEmpty ? number : stripped),
                             originCode: String(route.1), destinationCode: String(route.2),
                             departure: departure)
            }
        }.sorted { $0.departure < $1.departure }
    }
}

enum VisionTripItinerary {
    /// O roteiro é pessoal e fica fora do git; builds sem ele mostram a seção vazia.
    static var isAvailable: Bool {
        Bundle.main.url(forResource: "TripItinerary", withExtension: "json") != nil
    }

    static func load() throws -> [VisionTripDay] {
        guard let url = Bundle.main.url(forResource: "TripItinerary", withExtension: "json") else {
            throw VisionTripError.missingItinerary
        }
        let days = try JSONDecoder().decode([VisionTripDay].self, from: Data(contentsOf: url))
        return VisionTripCalendar.resolveYears(days)
    }
}

enum VisionTripError: LocalizedError {
    case missingItinerary, weatherUnavailable

    var errorDescription: String? {
        switch self {
        case .missingItinerary: "Roteiro não encontrado no app."
        case .weatherUnavailable: "Previsão do tempo indisponível."
        }
    }
}

struct VisionTripAirport {
    let code: String
    let name: String
    let latitude: Double
    let longitude: Double

    var timeZone: TimeZone? {
        let identifier: String
        switch code {
        case "RAO", "LDB", "GRU", "VCP": identifier = "America/Sao_Paulo"
        case "MAD": identifier = "Europe/Madrid"
        case "LGW", "LHR", "LCY": identifier = "Europe/London"
        case "LIS": identifier = "Europe/Lisbon"
        default: return nil
        }
        return TimeZone(identifier: identifier)
    }

    static let known: [String: Self] = [
        "RAO": .init(code: "RAO", name: "Ribeirão Preto", latitude: -21.1392477, longitude: -47.7765262),
        "LDB": .init(code: "LDB", name: "Londrina", latitude: -23.328542, longitude: -51.1377836),
        "GRU": .init(code: "GRU", name: "Guarulhos", latitude: -23.4262732, longitude: -46.4816737),
        "MAD": .init(code: "MAD", name: "Madri", latitude: 40.4944735, longitude: -3.5671731),
        "LGW": .init(code: "LGW", name: "Londres Gatwick", latitude: 51.1537, longitude: -0.1821),
        "LHR": .init(code: "LHR", name: "Londres Heathrow", latitude: 51.472515, longitude: -0.4877331),
        "LCY": .init(code: "LCY", name: "London City", latitude: 51.5042655, longitude: 0.0549024),
        "LIS": .init(code: "LIS", name: "Lisboa", latitude: 38.7809981, longitude: -9.1318608),
        "VCP": .init(code: "VCP", name: "Campinas Viracopos", latitude: -23.0074, longitude: -47.1344)
    ]
}

struct VisionTripWeather {
    let airport: VisionTripAirport
    let temperature: Double
    let weatherCode: Int
    let hours: [Hour]
    let fetchedAt: Date

    struct Hour: Identifiable {
        let time: Date
        let temperature: Double
        let rainChance: Int
        let weatherCode: Int
        var id: Date { time }
    }

    var description: String {
        switch weatherCode {
        case 0: "Céu limpo"
        case 1...3: "Nuvens"
        case 45, 48: "Nevoeiro"
        case 51...67, 80...82: "Chuva"
        case 71...77, 85, 86: "Neve"
        case 95...99: "Tempestade"
        default: "Condição atual"
        }
    }

    var symbol: String {
        switch weatherCode {
        case 0: "sun.max.fill"
        case 1...3: "cloud.sun.fill"
        case 45, 48: "cloud.fog.fill"
        case 51...67, 80...82: "cloud.rain.fill"
        case 71...77, 85, 86: "cloud.snow.fill"
        case 95...99: "cloud.bolt.rain.fill"
        default: "cloud.fill"
        }
    }
}

private struct OpenMeteoTripResponse: Decodable {
    struct Current: Decodable { let temperature_2m: Double; let weather_code: Int }
    struct Hourly: Decodable {
        let time: [Int]
        // Open-Meteo sends null for hours past some models' range.
        let temperature_2m: [Double?]
        let precipitation_probability: [Int?]
        let weather_code: [Int?]
    }
    let current: Current
    let hourly: Hourly
}

enum VisionTripWeatherService {
    static func fetch(_ airport: VisionTripAirport) async throws -> VisionTripWeather {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            .init(name: "latitude", value: String(airport.latitude)),
            .init(name: "longitude", value: String(airport.longitude)),
            .init(name: "current", value: "temperature_2m,weather_code"),
            .init(name: "hourly", value: "temperature_2m,precipitation_probability,weather_code"),
            .init(name: "timezone", value: "auto"),
            .init(name: "timeformat", value: "unixtime"),
            .init(name: "forecast_days", value: "16")
        ]
        guard let url = components.url else { throw VisionTripError.weatherUnavailable }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw VisionTripError.weatherUnavailable
        }
        return try decode(data, airport: airport)
    }

    static func decode(_ data: Data, airport: VisionTripAirport) throws -> VisionTripWeather {
        guard let result = try? JSONDecoder().decode(OpenMeteoTripResponse.self, from: data) else {
            throw VisionTripError.weatherUnavailable
        }
        let count = min(result.hourly.time.count, result.hourly.temperature_2m.count,
                        result.hourly.precipitation_probability.count, result.hourly.weather_code.count)
        let hours = (0..<count).compactMap { index -> VisionTripWeather.Hour? in
            guard let temperature = result.hourly.temperature_2m[index],
                  let rainChance = result.hourly.precipitation_probability[index],
                  let weatherCode = result.hourly.weather_code[index] else { return nil }
            return VisionTripWeather.Hour(time: Date(timeIntervalSince1970: TimeInterval(result.hourly.time[index])),
                                          temperature: temperature, rainChance: rainChance, weatherCode: weatherCode)
        }
        return .init(airport: airport, temperature: result.current.temperature_2m,
                     weatherCode: result.current.weather_code, hours: hours, fetchedAt: Date())
    }
}
