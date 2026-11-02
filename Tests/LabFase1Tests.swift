import Foundation
import SwiftUI
import Testing
@testable import MeuLabVision

@Suite("PollingScheduler")
@MainActor
struct PollingSchedulerTests {
    @Test func pollsOnlyWhenActive() {
        #expect(PollingScheduler.shouldPoll(.active))
        #expect(!PollingScheduler.shouldPoll(.inactive))
        #expect(!PollingScheduler.shouldPoll(.background))
    }

    @Test func keyChangesWithIdOrPhase() {
        #expect(PollingKey(id: 1, active: true) == PollingKey(id: 1, active: true))
        #expect(PollingKey(id: 1, active: true) != PollingKey(id: 2, active: true))
        #expect(PollingKey(id: 1, active: true) != PollingKey(id: 1, active: false))
    }

    @Test func runsImmediatelyThenRepeatsUntilCancelled() async {
        var count = 0
        let task = Task { @MainActor in
            await PollingScheduler.run(every: .milliseconds(10)) { count += 1 }
        }
        try? await Task.sleep(for: .milliseconds(120))
        task.cancel()
        await task.value
        let stopped = count
        #expect(stopped >= 2)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(count == stopped)
    }

    @Test func skipsImmediateRunWhenAsked() async {
        var count = 0
        let task = Task { @MainActor in
            await PollingScheduler.run(every: .seconds(60), immediately: false) { count += 1 }
        }
        try? await Task.sleep(for: .milliseconds(30))
        task.cancel()
        await task.value
        #expect(count == 0)
    }

    @Test func cancelledBeforeStartNeverRuns() async {
        var count = 0
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            await PollingScheduler.run(every: .milliseconds(1)) { count += 1 }
        }
        await task.value
        #expect(count == 0)
    }
}

@Suite("Séries – chave de progresso")
struct SeriesProgressKeyTests {
    let root = URL(fileURLWithPath: "/Volumes/Midia/Series")

    @Test func keyIsPathRelativeToRoot() {
        let file = root.appending(path: "Dark/S01/Dark.S01E01.mkv")
        #expect(VisionSeriesLibrary.progressKey(for: file, root: root) == "Dark/S01/Dark.S01E01.mkv")
    }

    @Test func sameFileNameInDifferentSeriesGetsDistinctKeys() {
        let a = root.appending(path: "Show A/S01E01.mkv")
        let b = root.appending(path: "Show B/S01E01.mkv")
        #expect(VisionSeriesLibrary.progressKey(for: a, root: root)
                != VisionSeriesLibrary.progressKey(for: b, root: root))
    }

    @Test func fileOutsideRootFallsBackToAbsolutePath() {
        let file = URL(fileURLWithPath: "/Volumes/Outro/S01E01.mkv")
        #expect(VisionSeriesLibrary.progressKey(for: file, root: root) == "/Volumes/Outro/S01E01.mkv")
    }
}

@Suite("Viagem – calendário")
struct TripCalendarTests {
    private func day(_ date: String, _ weekday: String) throws -> VisionTripDay {
        let json = #"{"id":"\#(date)","date":"\#(date)","weekday":"\#(weekday)","title":"t","tone":"blue","events":[]}"#
        return try JSONDecoder().decode(VisionTripDay.self, from: Data(json.utf8))
    }

    @Test func parsesAllPortugueseMonths() {
        let names = ["jan", "fev", "mar", "abr", "mai", "jun", "jul", "ago", "set", "out", "nov", "dez"]
        for (index, name) in names.enumerated() {
            #expect(VisionTripCalendar.dayMonth("5 \(name)")?.month == index + 1)
        }
        #expect(VisionTripCalendar.dayMonth("5 Outubro")?.month == 10)
        #expect(VisionTripCalendar.dayMonth("xx out") == nil)
    }

    @Test func parsesWeekdaysWithAccents() {
        #expect(VisionTripCalendar.weekday("domingo") == 1)
        #expect(VisionTripCalendar.weekday("quinta-feira") == 5)
        #expect(VisionTripCalendar.weekday("Sábado") == 7)
    }

    @Test func infersYearFromWeekday() {
        // 22/10/2026 é quinta; 2020 e 2037 também casam, 2026 é o mais próximo da referência.
        #expect(VisionTripCalendar.baseYear(for: [(22, 10, 5)], referenceYear: 2026) == 2026)
        // 22/10/2027 é sexta.
        #expect(VisionTripCalendar.baseYear(for: [(22, 10, 6)], referenceYear: 2026) == 2027)
    }

    @Test func rollsOverDecemberToJanuary() {
        #expect(VisionTripCalendar.rolledYears(months: [12, 12, 1, 1], base: 2026) == [2026, 2026, 2027, 2027])
    }

    @Test func resolvesYearsAcrossNewYear() throws {
        // 31/12/2026 quinta, 01/01/2027 sexta.
        let days = VisionTripCalendar.resolveYears(
            [try day("31 dez", "quinta-feira"), try day("1 jan", "sexta-feira")], referenceYear: 2026)
        #expect(days.map(\.year) == [2026, 2027])
    }

    @Test(.enabled(if: VisionTripItinerary.isAvailable)) func bundledItineraryResolvesTo2026() throws {
        let days = try VisionTripItinerary.load()
        #expect(!days.isEmpty)
        #expect(days.allSatisfy { $0.year == 2026 })
        #expect(VisionTripCalendar.rangeLabel(days)?.hasSuffix("de 2026") == true)
    }
}
