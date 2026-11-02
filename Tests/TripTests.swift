import Foundation
import Testing
@testable import MeuLabVision

@Suite("Viagem")
struct TripTests {
    let flights: [VisionTripFlight]

    init() throws {
        flights = VisionTripFlight.flights(in: try Fixture.decode([VisionTripDay].self, "trip_itinerary"))
    }

    private func utc(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

    @Test func extractsOnlyDatedNonPendingFlightsSorted() {
        #expect(flights.map(\.displayCode) == ["AD 9400", "G3 9405", "UX 9158"])
        #expect(flights.map(\.ident) == ["AD9400", "G39405", "UX9158"])
        #expect(flights.map(\.route) == ["LHR → LIS", "RAO → GRU", "GRU → MAD"])
    }

    @Test func departureUsesEventTimeZone() {
        #expect(flights[0].departure == utc("2026-10-22T22:50:00Z"))
        #expect(flights[1].departure == utc("2026-10-23T09:10:00Z"))
        #expect(flights[2].departure == utc("2026-10-24T01:30:00Z"))
    }

    @Test func plannedArrivalSameDay() {
        #expect(flights[1].plannedArrival == utc("2026-10-23T10:20:00Z"))
    }

    @Test func plannedArrivalWithExplicitDate() {
        #expect(flights[2].plannedArrival == utc("2026-10-24T12:25:00Z"))
    }

    @Test func plannedArrivalRollsOverMidnight() {
        #expect(flights[0].plannedArrival == utc("2026-10-22T23:40:00Z"))
    }

    @Test(.enabled(if: VisionTripItinerary.isAvailable)) func bundledItineraryHasEightFlights() throws {
        let days = try VisionTripItinerary.load()
        let all = VisionTripFlight.flights(in: days)
        #expect(all.count == 8)
        #expect(all.allSatisfy { flight in flight.plannedArrival.map { $0 > flight.departure } ?? true })
        #expect(zip(all, all.dropFirst()).allSatisfy { $0.departure <= $1.departure })
    }
}
