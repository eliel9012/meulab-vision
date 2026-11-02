import Foundation

struct OpenMeteoForecast: Decodable, Sendable {
    let hourly: Hourly
    let daily: Daily

    struct Hourly: Decodable, Sendable {
        let time: [String]
        let temperature: [Double]
        let humidity: [Int]
        let rainChance: [Int]
        let rain: [Double]
        let wind: [Double]
        let uv: [Double]
        enum CodingKeys: String, CodingKey {
            case time
            case temperature = "temperature_2m"
            case humidity = "relative_humidity_2m"
            case rainChance = "precipitation_probability"
            case rain = "precipitation"
            case wind = "wind_speed_10m"
            case uv = "uv_index"
        }
    }

    struct Daily: Decodable, Sendable {
        let time: [String]
        let max: [Double]
        let min: [Double]
        let rain: [Double]
        let rainChance: [Int]
        let uv: [Double]
        let sunrise: [String]
        let sunset: [String]
        enum CodingKeys: String, CodingKey {
            case time, sunrise, sunset
            case max = "temperature_2m_max"
            case min = "temperature_2m_min"
            case rain = "precipitation_sum"
            case rainChance = "precipitation_probability_max"
            case uv = "uv_index_max"
        }
    }

    struct HourPoint: Identifiable {
        let time: String
        let temperature: Double
        let humidity: Int
        let rainChance: Int
        let rain: Double
        let wind: Double
        let uv: Double
        var id: String { time }
        var day: String { String(time.prefix(10)) }
        var hour: String { String(time.suffix(5)) }
    }

    struct DayPoint: Identifiable {
        let date: String
        let max: Double
        let min: Double
        let rain: Double
        let rainChance: Int
        let uv: Double
        let sunrise: String
        let sunset: String
        var id: String { date }
    }

    var hours: [HourPoint] {
        let h = hourly
        let count = [h.time.count, h.temperature.count, h.humidity.count, h.rainChance.count,
                     h.rain.count, h.wind.count, h.uv.count].min() ?? 0
        return (0..<count).map { i in
            HourPoint(time: h.time[i], temperature: h.temperature[i], humidity: h.humidity[i],
                      rainChance: h.rainChance[i], rain: h.rain[i], wind: h.wind[i], uv: h.uv[i])
        }
    }

    var days: [DayPoint] {
        let d = daily
        let count = [d.time.count, d.max.count, d.min.count, d.rain.count, d.rainChance.count,
                     d.uv.count, d.sunrise.count, d.sunset.count].min() ?? 0
        return (0..<count).map { i in
            DayPoint(date: d.time[i], max: d.max[i], min: d.min[i], rain: d.rain[i],
                     rainChance: d.rainChance[i], uv: d.uv[i], sunrise: d.sunrise[i], sunset: d.sunset[i])
        }
    }
}
