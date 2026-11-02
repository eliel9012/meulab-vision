import Foundation
import Testing
@testable import MeuLabCore

@Test func nowPlayingEqualityIgnoresTimestamp() throws {
    func decode(_ timestamp: String) throws -> NowPlaying {
        let json = """
        {"timestamp":"\(timestamp)","stream_url":"s","radio_name":"r","artist":"A","title":"T","has_itunes":false}
        """
        return try JSONDecoder().decode(NowPlaying.self, from: Data(json.utf8))
    }
    #expect(try decode("1") == decode("2"))
    #expect(try decode("1").displayTitle == "A - T")
}

@Test func flightAwareTimeParsesISO() {
    #expect(FlightAwareTime.parse("2026-10-30T12:00:00Z") != nil)
    #expect(FlightAwareTime.parse("2026-10-30T12:00:00.123Z") != nil)
    #expect(FlightAwareTime.parse(nil) == nil)
}

@Test func publicInitBuildsWeather() {
    let point = HourlyWeatherPoint(time: "2026-10-30T14:00", tempC: 25, humidity: nil, rainChance: 80,
                                   rainMm: 2, uvIndex: 3, windKmh: nil)
    #expect(point.dayKey == "2026-10-30")
    #expect(point.description == nil)
}
