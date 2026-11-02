import Foundation

struct AircraftSnapshot: Sendable {
    let generatedAt: Date?
    let messages: Int?
    let aircraft: [Aircraft]
}

enum AircraftDecoder {
    static func decode(_ data: Data) throws -> AircraftSnapshot {
        let response = try JSONDecoder().decode(ReadsbAircraftResponse.self, from: data)
        // Deduplicate by ICAO address while preserving original order.
        var seen = Set<String>()
        let aircraft = response.aircraft.compactMap(Aircraft.init(wire:)).filter { seen.insert($0.hex).inserted }
        let generatedAt = response.now.flatMap { $0.isFinite ? Date(timeIntervalSince1970: $0) : nil }
        return AircraftSnapshot(generatedAt: generatedAt, messages: response.messages, aircraft: aircraft)
    }
}
