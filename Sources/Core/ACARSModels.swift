import Foundation

struct ACARSDashboard: Decodable, Sendable {
    let today: Period
    let last24h: Period
    let lastHour: Int
    let topAircraft: [Aircraft]
    let topLabels: [LabelCount]
    struct Period: Decodable, Sendable {
        let messages: Int
        let flights: Int
        let aircraft: Int
        let peakHour: String?
        enum CodingKeys: String, CodingKey {
            case messages, flights, aircraft
            case peakHour = "peak_hour"
        }
    }
    struct Aircraft: Decodable, Sendable, Identifiable {
        let tail: String
        let flight: String?
        let count: Int
        var id: String { tail }
    }
    struct LabelCount: Decodable, Sendable, Identifiable {
        let label: String
        let description: String?
        let count: Int
        var id: String { label }
    }
    enum CodingKeys: String, CodingKey {
        case today
        case last24h = "last_24h"
        case lastHour = "last_hour"
        case topAircraft = "top_aircraft"
        case topLabels = "top_labels"
    }
}

struct ACARSHourly: Decodable, Sendable {
    let hours: [Hour]
    struct Hour: Decodable, Sendable, Identifiable {
        let hour: String
        let messages: Int
        let flights: Int
        var id: String { hour }
    }
}

struct ACARSHistory: Decodable, Sendable {
    let last7Days: [Day]
    let last24hHours: [Hour]
    struct Day: Decodable, Sendable, Identifiable {
        let day: String
        let messages: Int
        var id: String { day }
    }
    struct Hour: Decodable, Sendable, Identifiable {
        let hour: String
        let messages: Int
        var id: String { hour }
    }
    enum CodingKeys: String, CodingKey {
        case last7Days = "last_7_days", last24hHours = "last_24h_hours"
    }
}

struct ACARSList: Decodable, Sendable { let messages: [ACARSItem] }
struct ACARSDetail: Decodable, Sendable { let message: ACARSItem }
struct ACARSSearch: Decodable, Sendable { let messages: [ACARSItem] }

struct ACARSItem: Decodable, Sendable, Identifiable {
    let id: Int
    let flight: String?
    let tail: String?
    let label: String?
    let labelDesc: String?
    let departure: String?
    let destination: String?
    let text: String?
    let time: String
    let messageType: String?
    let stationId: String?
    let eta: String?
    let lat: Double?
    let lon: Double?
    let altitudeFt: Double?
    let freqMhz: Double?
    enum CodingKeys: String, CodingKey {
        case id, flight, tail, label, departure, destination, text, time, eta, lat, lon
        case labelDesc = "label_desc", messageType = "message_type", stationId = "station_id"
        case altitudeFt = "altitude_ft", freqMhz = "freq_mhz"
    }
    var title: String { flight ?? tail ?? "Sem identificação" }
    var route: String? {
        guard departure != nil || destination != nil else { return nil }
        return "\(departure ?? "—") → \(destination ?? "—")"
    }
}
