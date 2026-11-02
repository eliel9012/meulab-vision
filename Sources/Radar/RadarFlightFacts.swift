import Foundation

struct RadarFlightFact: Identifiable, Equatable {
    let title: String
    let value: String
    let symbol: String

    var id: String { title }
}

/// Live ADS-B readings of one aircraft, as shown in the radar panel and the flight card.
enum RadarFlightFacts {
    static func subtitle(_ aircraft: Aircraft) -> String? {
        let parts = [aircraft.aircraftType, aircraft.description, aircraft.registration]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func facts(for aircraft: Aircraft, positionAge: Double?) -> [RadarFlightFact] {
        [
            .init(title: "Altitude", value: altitude(aircraft), symbol: "mountain.2"),
            .init(title: "Velocidade",
                  value: aircraft.speedKilometersPerHour.map { "\(Int($0.rounded()).formatted()) km/h" } ?? "—",
                  symbol: "speedometer"),
            .init(title: "Rumo", value: aircraft.trackDegrees.map(heading) ?? "—", symbol: "location.north"),
            .init(title: "Razão vertical", value: verticalRate(aircraft.verticalRateFeetPerMinute),
                  symbol: "arrow.up.arrow.down"),
            .init(title: "Distância", value: distance(aircraft), symbol: "antenna.radiowaves.left.and.right"),
            .init(title: "Posição", value: positionAge.map(age) ?? "—", symbol: "clock"),
            .init(title: "Squawk", value: aircraft.squawk ?? "—", symbol: "number"),
            .init(title: "Sinal",
                  value: aircraft.rssi.map { "\($0.formatted(.number.precision(.fractionLength(1)))) dBFS" } ?? "—",
                  symbol: "dot.radiowaves.right")
        ]
    }

    private static func altitude(_ aircraft: Aircraft) -> String {
        if aircraft.altitudeKind == .ground { return AltitudeKind.ground.rawValue }
        return aircraft.altitudeFeet.map { "\(Int($0.rounded()).formatted()) ft" } ?? "—"
    }

    static func heading(_ degrees: Double) -> String {
        let names = ["N", "NE", "L", "SE", "S", "SO", "O", "NO"]
        let index = Int((degrees / 45).rounded()) % names.count
        return "\(Int(degrees))° \(names[index])"
    }

    static func verticalRate(_ feetPerMinute: Double?) -> String {
        guard let feetPerMinute else { return "—" }
        if abs(feetPerMinute) < 100 { return "Nivelado" }
        return "\(feetPerMinute > 0 ? "↑" : "↓") \(Int(abs(feetPerMinute)).formatted()) ft/min"
    }

    private static func distance(_ aircraft: Aircraft) -> String {
        guard let latitude = aircraft.latitude, let longitude = aircraft.longitude else { return "—" }
        let position = GeodeticCoordinate(latitudeDegrees: latitude, longitudeDegrees: longitude, altitudeMeters: 0)
        let meters = Geodesy.enu(position, relativeTo: Geodesy.approximateFranca).horizontalDistanceMeters
        return "\(Int((meters / 1_000).rounded()).formatted()) km"
    }

    static func age(_ seconds: Double) -> String {
        seconds < 60 ? "há \(Int(seconds)) s" : "há \(Int(seconds / 60)) min"
    }
}
