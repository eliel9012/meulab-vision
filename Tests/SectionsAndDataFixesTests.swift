import Foundation
import Testing
@testable import MeuLabVision

@Suite("Abas e dados")
struct SectionsAndDataFixesTests {
    @Test func tabBarFitsItsLimitAndReachesEverySection() {
        #expect(VisionSection.tabs.count <= 8)
        for section in VisionSection.allCases {
            #expect(VisionSection.tabs.contains(section.tabHost))
            if section.tabHost != section { #expect(section.tabHost.tabSiblings.contains(section)) }
        }
    }

    @Test func tabKeepsOwnSectionFirstInPicker() {
        #expect(VisionSection.system.tabSiblings == [.system, .infrastructure])
        #expect(VisionSection.series.tabSiblings == [.radio, .series])
        #expect(VisionSection.acars.tabSiblings.isEmpty)
    }

    @Test func parsesServerLocalTimestampAsSaoPaulo() {
        let date = Formatters.parseISO("2026-10-30T13:24:45.453560")
        #expect(date == ISO8601DateFormatter().date(from: "2026-10-30T16:24:45Z"))
    }

    @Test func zonedTimestampsKeepTheirZone() {
        #expect(Formatters.parseISO("2026-10-30T13:24:45Z") == ISO8601DateFormatter().date(from: "2026-10-30T13:24:45Z"))
        #expect(Formatters.parseISO("sem data") == nil)
    }

    @Test func tripWeatherSkipsHoursWithNulls() throws {
        let json = """
        {"current":{"temperature_2m":14.5,"weather_code":0},
         "hourly":{"time":[1000,2000,3000],"temperature_2m":[10.0,null,12.0],
                   "precipitation_probability":[5,6,null],"weather_code":[1,2,3]}}
        """
        let airport = try #require(VisionTripAirport.known["LCY"])
        let weather = try VisionTripWeatherService.decode(Data(json.utf8), airport: airport)
        #expect(weather.hours.map(\.temperature) == [10.0])
        #expect(weather.temperature == 14.5)
    }

    @Test func invalidTripWeatherGivesReadableError() throws {
        let airport = try #require(VisionTripAirport.known["LCY"])
        #expect(throws: VisionTripError.self) {
            try VisionTripWeatherService.decode(Data("{}".utf8), airport: airport)
        }
    }
}
