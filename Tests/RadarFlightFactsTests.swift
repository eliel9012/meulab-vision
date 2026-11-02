import Foundation
import Testing
@testable import MeuLabVision

@Suite("Dados do avião selecionado")
struct RadarFlightFactsTests {
    private func aircraft(_ fields: String) throws -> Aircraft {
        let json = #"{"now":1,"aircraft":[{"hex":"a1",\#(fields)}]}"#
        return try #require(AircraftDecoder.decode(Data(json.utf8)).aircraft.first)
    }

    private func value(_ title: String, _ facts: [RadarFlightFact]) -> String? {
        facts.first { $0.title == title }?.value
    }

    @Test func fullAircraftFillsEveryFact() throws {
        let flight = try aircraft(#""flight":"GLO1406","r":"PR-GXA","t":"B738","desc":"BOEING 737-800","lat":-20.51,"lon":-47.40,"alt_baro":900,"gs":100,"track":352,"baro_rate":-1200,"squawk":"2041","rssi":-12.5"#)
        let facts = RadarFlightFacts.facts(for: flight, positionAge: 3)

        #expect(facts.count == 8)
        #expect(!facts.map(\.value).contains("—"))
        #expect(value("Altitude", facts) == "900 ft")
        #expect(value("Rumo", facts) == "352° N")
        #expect(value("Razão vertical", facts) == "↓ \(1_200.formatted()) ft/min")
        #expect(value("Distância", facts) == "0 km")
        #expect(value("Posição", facts) == "há 3 s")
        #expect(value("Squawk", facts) == "2041")
        #expect(RadarFlightFacts.subtitle(flight) == "B738 · BOEING 737-800 · PR-GXA")
    }

    @Test func missingDataShowsADash() throws {
        let flight = try aircraft(#""flight":"X""#)
        let facts = RadarFlightFacts.facts(for: flight, positionAge: nil)
        #expect(facts.allSatisfy { $0.value == "—" })
        #expect(RadarFlightFacts.subtitle(flight) == nil)
    }

    @Test func groundAircraftSaysSo() throws {
        #expect(value("Altitude", RadarFlightFacts.facts(for: try aircraft(#""alt_baro":"ground""#), positionAge: nil)) == "Solo")
    }

    @Test func headingUsesPortugueseCardinals() {
        #expect(RadarFlightFacts.heading(0) == "0° N")
        #expect(RadarFlightFacts.heading(90) == "90° L")
        #expect(RadarFlightFacts.heading(225) == "225° SO")
        #expect(RadarFlightFacts.heading(359) == "359° N")
    }

    @Test func verticalRateAndAgeAreReadable() {
        #expect(RadarFlightFacts.verticalRate(nil) == "—")
        #expect(RadarFlightFacts.verticalRate(64) == "Nivelado")
        #expect(RadarFlightFacts.verticalRate(800) == "↑ 800 ft/min")
        #expect(RadarFlightFacts.age(59) == "há 59 s")
        #expect(RadarFlightFacts.age(125) == "há 2 min")
    }
}
