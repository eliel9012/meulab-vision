import Foundation

/// Wire format of readsb/dump1090 aircraft.json. Individual fields are deliberately optional.
struct ReadsbAircraftResponse: Decodable, Sendable {
    let now: Double?
    let messages: Int?
    let aircraft: [ReadsbAircraft]

    enum CodingKeys: String, CodingKey { case now, messages, aircraft }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        now = container.lossyDouble(.now)
        messages = try? container.decodeIfPresent(Int.self, forKey: .messages)
        aircraft = (try? container.decodeIfPresent([ReadsbAircraft].self, forKey: .aircraft)) ?? []
    }
}

/// Barometric altitude in readsb can be a number of feet or the string "ground".
enum ReadsbBarometricAltitude: Equatable, Sendable {
    case feet(Double)
    case ground
    case unknown
}

struct ReadsbAircraft: Decodable, Sendable {
    let hex: String
    let sourceType: String?
    let flight: String?
    let registration: String?
    let aircraftType: String?
    let description: String?
    let latitude: Double?
    let longitude: Double?
    let barometricAltitude: ReadsbBarometricAltitude
    let geometricAltitudeFeet: Double?
    let groundSpeedKnots: Double?
    let trackDegrees: Double?
    let barometricRate: Double?
    let geometricRate: Double?
    let seen: Double?
    let seenPosition: Double?
    let rssi: Double?
    let category: String?
    let squawk: String?

    enum CodingKeys: String, CodingKey {
        case hex, type, flight, r, t, desc, lat, lon, alt_baro, alt_geom
        case gs, track, baro_rate, geom_rate, seen, seen_pos, rssi, category, squawk
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hex = (try? c.decode(String.self, forKey: .hex)) ?? ""
        sourceType = try? c.decodeIfPresent(String.self, forKey: .type)
        flight = try? c.decodeIfPresent(String.self, forKey: .flight)
        registration = try? c.decodeIfPresent(String.self, forKey: .r)
        aircraftType = try? c.decodeIfPresent(String.self, forKey: .t)
        description = try? c.decodeIfPresent(String.self, forKey: .desc)
        latitude = c.lossyDouble(.lat)
        longitude = c.lossyDouble(.lon)
        geometricAltitudeFeet = c.lossyDouble(.alt_geom)
        groundSpeedKnots = c.lossyDouble(.gs)
        trackDegrees = c.lossyDouble(.track)
        barometricRate = c.lossyDouble(.baro_rate)
        geometricRate = c.lossyDouble(.geom_rate)
        seen = c.lossyDouble(.seen)
        seenPosition = c.lossyDouble(.seen_pos)
        rssi = c.lossyDouble(.rssi)
        category = try? c.decodeIfPresent(String.self, forKey: .category)
        squawk = (try? c.decodeIfPresent(String.self, forKey: .squawk))
            ?? (try? c.decode(Int.self, forKey: .squawk)).map(String.init)

        if let feet = c.lossyDouble(.alt_baro) {
            barometricAltitude = .feet(feet)
        } else if let word = try? c.decode(String.self, forKey: .alt_baro),
                  word.lowercased() == "ground" {
            barometricAltitude = .ground
        } else {
            barometricAltitude = .unknown
        }
    }
}

extension KeyedDecodingContainer {
    func lossyDouble(_ key: Key) -> Double? {
        if let v = try? decode(Double.self, forKey: key), v.isFinite { return v }
        if let v = try? decode(String.self, forKey: key),
           let parsed = Double(v), parsed.isFinite { return parsed }
        return nil
    }
}
