import Foundation

enum AltitudeKind: String, Sendable {
    case barometric = "Barométrica"
    case geometric = "Geométrica"
    case ground = "Solo"
    case unavailable = "Indisponível"
}

struct Aircraft: Identifiable, Equatable, Sendable {
    let hex: String
    let callsign: String
    let registration: String?
    let aircraftType: String?
    let description: String?
    let latitude: Double?
    let longitude: Double?
    let altitudeMeters: Double?
    let altitudeKind: AltitudeKind
    let geometricAltitudeMeters: Double?
    let speedKnots: Double?
    let trackDegrees: Double?
    let verticalRateFeetPerMinute: Double?
    let seenSeconds: Double?
    let seenPositionSeconds: Double?
    let rssi: Double?
    let category: String?
    let squawk: String?
    let sourceType: String?

    var id: String { hex }
    var hasPosition: Bool { latitude != nil && longitude != nil }
    var speedKilometersPerHour: Double? { speedKnots.map { $0 * 1.852 } }
    var altitudeFeet: Double? { altitudeMeters.map { $0 / 0.3048 } }

    /// readsb ages are relative to the JSON generation instant, not the local receipt time.
    func positionAge(at receivedAt: Date, now: Date) -> Double? {
        guard let age = seenPositionSeconds else { return nil }
        return age + max(0, now.timeIntervalSince(receivedAt))
    }

    func hasRecentPosition(at receivedAt: Date, now: Date, maxAge: Double = 30) -> Bool {
        guard hasPosition, let age = positionAge(at: receivedAt, now: now) else { return false }
        return age <= maxAge
    }
}

extension Aircraft {
    init?(wire: ReadsbAircraft) {
        let id = wire.hex.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !id.isEmpty else { return nil }
        hex = id
        let flight = wire.flight?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        callsign = flight.isEmpty ? id.uppercased() : flight
        registration = wire.registration?.trimmingCharacters(in: .whitespacesAndNewlines)
        aircraftType = wire.aircraftType
        description = wire.description
        if let lat = wire.latitude, let lon = wire.longitude,
           lat.isFinite, lon.isFinite, (-90...90).contains(lat), (-180...180).contains(lon) {
            latitude = lat
            longitude = lon
        } else {
            latitude = nil
            longitude = nil
        }
        geometricAltitudeMeters = wire.geometricAltitudeFeet.map { $0 * 0.3048 }
        switch wire.barometricAltitude {
        case .feet(let value):
            altitudeMeters = value * 0.3048
            altitudeKind = .barometric
        case .ground:
            altitudeMeters = 0
            altitudeKind = .ground
        case .unknown:
            altitudeMeters = geometricAltitudeMeters
            altitudeKind = geometricAltitudeMeters == nil ? .unavailable : .geometric
        }
        speedKnots = wire.groundSpeedKnots.flatMap { $0 >= 0 ? $0 : nil }
        trackDegrees = wire.trackDegrees.map {
            let remainder = $0.truncatingRemainder(dividingBy: 360)
            return remainder < 0 ? remainder + 360 : remainder
        }
        verticalRateFeetPerMinute = wire.barometricRate ?? wire.geometricRate
        seenSeconds = wire.seen.flatMap { $0 >= 0 ? $0 : nil }
        seenPositionSeconds = wire.seenPosition.flatMap { $0 >= 0 ? $0 : nil }
        rssi = wire.rssi
        category = wire.category
        squawk = wire.squawk
        sourceType = wire.sourceType
    }
}
