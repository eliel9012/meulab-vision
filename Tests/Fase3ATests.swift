import Foundation
import Testing
@testable import MeuLabVision

@Suite("Fase 3A · shell and day×hour binning")
struct Fase3ATests {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    @Test("VisionSection survives a Codable round-trip (window values, SceneStorage)")
    func sectionCodableRoundTrip() throws {
        let data = try JSONEncoder().encode(VisionSection.allCases)
        let decoded = try JSONDecoder().decode([VisionSection].self, from: data)
        #expect(decoded == VisionSection.allCases)
        for section in VisionSection.allCases {
            #expect(VisionSection(rawValue: section.rawValue) == section)
        }
        #expect(Set(VisionSection.allCases).count == VisionSection.allCases.count)
    }

    @MainActor
    @Test("Only system/infra/radio refresh through the store")
    func storeBackedSections() {
        let storeBacked = VisionSection.allCases.filter { VisionLabStore.usesStoreData($0) }
        #expect(Set(storeBacked) == [.system, .infrastructure, .radio])
    }

    @Test("Timestamp parsing accepts the API formats", arguments: [
        "2026-10-30T14:15:00Z",
        "2026-10-30T14:15:00.123Z",
        "2026-10-30T14:15:00+00:00",
        "2026-10-30T14:15:00",
        "2026-10-30 14:15:00",
        "2026-10-30 14:15",
    ])
    func parsesTimestamps(_ raw: String) throws {
        let utc = TimeZone(identifier: "UTC")!
        let date = try #require(HourDayBinning.parseTimestamp(raw, timeZone: utc))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        #expect(calendar.component(.hour, from: date) == 14)
        #expect(calendar.component(.day, from: date) == 30)
    }

    @Test("Garbage timestamps are rejected")
    func rejectsGarbage() {
        #expect(HourDayBinning.parseTimestamp("ontem") == nil)
        #expect(HourDayBinning.parseTimestamp("") == nil)
    }

    @Test("Samples are averaged per day and hour, oldest day first")
    func hourDayAverages() {
        let samples: [(timestamp: String, value: Double)] = [
            ("2026-10-29T10:00:00Z", 10),
            ("2026-10-29T10:30:00Z", 30),
            ("2026-10-29T11:00:00Z", 50),
            ("2026-10-30T10:15:00Z", 80),
            ("invalid", 999),
        ]
        let cells = HourDayBinning.hourDayAverages(samples, calendar: utc)
        #expect(cells.count == 3)
        #expect(cells.map(\.day) == [0, 0, 1])
        #expect(cells.map(\.hour) == [10, 11, 10])
        #expect(cells[0].value == 20)
        #expect(cells[2].value == 80)
        #expect(cells[0].dayLabel == "29/10")
        #expect(Set(cells.map(\.id)).count == cells.count)
    }

    @Test("Hour labels parse in every API shape", arguments: [
        ("14", 14), ("14:00", 14), ("2026-10-30 14:00", 14), ("2026-10-30T09:00:00Z", 9), ("24", nil), ("x", nil),
    ] as [(String, Int?)])
    func parsesHours(_ raw: String, _ expected: Int?) {
        #expect(HourDayBinning.parseHour(raw) == expected)
    }

    @Test("ACARS week matrix spreads each day total over the hourly profile")
    func acarsDistribution() {
        let cells = HourDayBinning.distribute(
            dailyTotals: [("2026-10-29", 100), ("2026-10-30", 40)],
            hourlyProfile: [("10:00", 3), ("11:00", 1), ("bad", 50)])
        #expect(cells.count == 4)
        let day0 = cells.filter { $0.day == 0 }
        #expect(day0.reduce(0) { $0 + $1.value } == 100)
        #expect(day0.first { $0.hour == 10 }?.value == 75)
        #expect(cells.filter { $0.day == 1 }.reduce(0) { $0 + $1.value } == 40)
        #expect(HourDayBinning.distribute(dailyTotals: [("d", 5)], hourlyProfile: []).isEmpty)
    }

    @MainActor
    @Test("Pushed windows are counted and block mission-control reopen")
    func pushedWindowTracking() {
        let windows = VisionWindowCoordinator()
        #expect(!windows.hasPushedWindow)
        windows.pushedWindowAppeared()
        #expect(windows.hasPushedWindow)
        windows.pushedWindowDisappeared()
        windows.pushedWindowDisappeared()
        #expect(windows.pushedWindowCount == 0)
    }

    @MainActor
    @Test("ACARS message cache resolves ids for the pushed window")
    func acarsCache() throws {
        let json = #"[{"id": 987654321, "flight": "TAM3400", "time": "2026-10-30 14:00:00"}]"#
        let items = try JSONDecoder().decode([ACARSItem].self, from: Data(json.utf8))
        ACARSMessageCache.shared.store(items)
        #expect(ACARSMessageCache.shared.message(987654321)?.flight == "TAM3400")
    }
}
