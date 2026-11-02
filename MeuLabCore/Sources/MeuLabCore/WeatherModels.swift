import Foundation

public struct WeatherData: Codable, Equatable, Sendable {
    public let timestamp: String
    public let location: String
    public let current: CurrentWeather
    public let today: TodayWeather
    public let forecast: [ForecastDay]
    public var hourly: [HourlyWeatherPoint]? = nil

    public init(timestamp: String, location: String, current: CurrentWeather, today: TodayWeather, forecast: [ForecastDay], hourly: [HourlyWeatherPoint]? = nil) {
        self.timestamp = timestamp
        self.location = location
        self.current = current
        self.today = today
        self.forecast = forecast
        self.hourly = hourly
    }
}

public struct CurrentWeather: Codable, Equatable, Sendable {
    public let tempC: Int
    public let feelsLikeC: Int
    public let humidity: Int
    public let windKmh: Int
    public let windDir: String
    public let description: String
    public let precipMm: Double
    public let uvIndex: Int
    public var weatherCode: Int? = nil
    public var isDaylight: Bool? = nil

    enum CodingKeys: String, CodingKey {
        case tempC = "temp_c"
        case feelsLikeC = "feels_like_c"
        case humidity
        case windKmh = "wind_kmh"
        case windDir = "wind_dir"
        case description
        case precipMm = "precip_mm"
        case uvIndex = "uv_index"
        case weatherCode = "weather_code"
        case isDaylight = "is_daylight"
    }

    public init(tempC: Int, feelsLikeC: Int, humidity: Int, windKmh: Int, windDir: String, description: String, precipMm: Double, uvIndex: Int, weatherCode: Int? = nil, isDaylight: Bool? = nil) {
        self.tempC = tempC
        self.feelsLikeC = feelsLikeC
        self.humidity = humidity
        self.windKmh = windKmh
        self.windDir = windDir
        self.description = description
        self.precipMm = precipMm
        self.uvIndex = uvIndex
        self.weatherCode = weatherCode
        self.isDaylight = isDaylight
    }
}

public struct TodayWeather: Codable, Equatable, Sendable {
    public let maxTempC: Int
    public let minTempC: Int
    public let rainChance: Int
    public let rainMm: Double
    public let uvIndex: Int
    public var description: String? = nil
    public var sunrise: String? = nil
    public var sunset: String? = nil

    enum CodingKeys: String, CodingKey {
        case maxTempC = "max_temp_c"
        case minTempC = "min_temp_c"
        case rainChance = "rain_chance"
        case rainMm = "rain_mm"
        case uvIndex = "uv_index"
        case description
        case sunrise
        case sunset
    }

    public init(maxTempC: Int, minTempC: Int, rainChance: Int, rainMm: Double, uvIndex: Int, description: String? = nil, sunrise: String? = nil, sunset: String? = nil) {
        self.maxTempC = maxTempC
        self.minTempC = minTempC
        self.rainChance = rainChance
        self.rainMm = rainMm
        self.uvIndex = uvIndex
        self.description = description
        self.sunrise = sunrise
        self.sunset = sunset
    }
}

public struct ForecastDay: Codable, Identifiable, Equatable, Sendable {
    public let date: String
    public let maxTempC: Int
    public let minTempC: Int
    public let rainChance: Int
    public let rainMm: Double
    public let uvIndex: Int
    public var description: String? = nil
    public var sunrise: String? = nil
    public var sunset: String? = nil

    public var id: String { date }

    enum CodingKeys: String, CodingKey {
        case date
        case maxTempC = "max_temp_c"
        case minTempC = "min_temp_c"
        case rainChance = "rain_chance"
        case rainMm = "rain_mm"
        case uvIndex = "uv_index"
        case description
        case sunrise
        case sunset
    }

    public var formattedDate: String {
        guard let date = CoreFormatters.apiDate.date(from: date) else {
            return self.date
        }
        return CoreFormatters.dayMonth.string(from: date).capitalized
    }

    public var weatherIcon: String {
        weatherSymbol(description: description, rainChance: rainChance)
    }

    public init(date: String, maxTempC: Int, minTempC: Int, rainChance: Int, rainMm: Double, uvIndex: Int, description: String? = nil, sunrise: String? = nil, sunset: String? = nil) {
        self.date = date
        self.maxTempC = maxTempC
        self.minTempC = minTempC
        self.rainChance = rainChance
        self.rainMm = rainMm
        self.uvIndex = uvIndex
        self.description = description
        self.sunrise = sunrise
        self.sunset = sunset
    }
}

public struct HourlyWeatherPoint: Codable, Identifiable, Equatable, Sendable {
    public let time: String
    public let tempC: Int
    public let humidity: Int?
    public let rainChance: Int
    public let rainMm: Double
    public let uvIndex: Int
    public let windKmh: Int?
    public var description: String? = nil

    public var id: String { time }

    enum CodingKeys: String, CodingKey {
        case time
        case tempC = "temp_c"
        case humidity
        case rainChance = "rain_chance"
        case rainMm = "rain_mm"
        case uvIndex = "uv_index"
        case windKmh = "wind_kmh"
        case description
    }

    public var weatherIcon: String {
        weatherSymbol(description: description, rainChance: rainChance)
    }

    public var dateValue: Date? {
        WeatherTimeParser.dateTime(from: time)
    }

    public var timeLabel: String {
        guard let date = dateValue else { return String(time.suffix(5)) }
        return CoreFormatters.time.string(from: date)
    }

    public var dayKey: String {
        guard let date = dateValue else { return String(time.prefix(10)) }
        return WeatherTimeParser.apiDay.string(from: date)
    }

    public init(time: String, tempC: Int, humidity: Int?, rainChance: Int, rainMm: Double, uvIndex: Int, windKmh: Int?, description: String? = nil) {
        self.time = time
        self.tempC = tempC
        self.humidity = humidity
        self.rainChance = rainChance
        self.rainMm = rainMm
        self.uvIndex = uvIndex
        self.windKmh = windKmh
        self.description = description
    }
}

private enum WeatherTimeParser {
    static let apiDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static let localDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return formatter
    }()

    static func dateTime(from raw: String) -> Date? {
        if let iso = CoreFormatters.isoDate.date(from: raw) ?? CoreFormatters.isoDateNoFrac.date(from: raw) {
            return iso
        }
        return localDateTime.date(from: raw)
    }
}

private func weatherSymbol(description: String?, rainChance: Int) -> String {
    let normalized = description?.lowercased() ?? ""

    if normalized.contains("tempestade") || normalized.contains("granizo") {
        return "cloud.bolt.rain.fill"
    }
    if normalized.contains("neve") {
        return "cloud.snow.fill"
    }
    if normalized.contains("garoa") || normalized.contains("chuva") || rainChance >= 70 {
        return "cloud.rain.fill"
    }
    if normalized.contains("nublado") || normalized.contains("nevoeiro") || rainChance >= 40 {
        return "cloud.sun.fill"
    }
    if rainChance >= 20 {
        return "cloud.sun.fill"
    }
    return "sun.max.fill"
}
