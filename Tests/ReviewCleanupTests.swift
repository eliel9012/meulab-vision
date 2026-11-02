import Foundation
import Testing
@testable import MeuLabVision

@Suite("Limpezas da revisão")
struct ReviewCleanupTests {
    @Test func negativeTrackIsNormalized() throws {
        let json = #"{"now":1,"aircraft":[{"hex":"a1","track":-10},{"hex":"a2","track":370},{"hex":"a3","track":90}]}"#
        let snapshot = try AircraftDecoder.decode(Data(json.utf8))
        #expect(snapshot.aircraft.map(\.trackDegrees) == [350, 10, 90])
    }

    @Test func sectionRawValueIsTheStableCaseName() {
        #expect(VisionSection(rawValue: "weather") == .weather)
        #expect(VisionSection(rawValue: "Clima") == nil)
        #expect(VisionSection.weather.title == "Clima")
        for section in VisionSection.allCases {
            #expect(section.rawValue == section.routeID)
            #expect(!section.title.isEmpty)
        }
    }

    @Test func isoDatesParseWithAndWithoutFraction() {
        #expect(Formatters.parseISO("2026-10-30T12:00:00Z") == Date(timeIntervalSince1970: 1_793_361_600))
        #expect(Formatters.parseISO("2026-10-30T12:00:00.500Z") == Date(timeIntervalSince1970: 1_793_361_600.5))
        #expect(Formatters.parseISO("ontem") == nil)
    }

    @Test func apiDateIsIndependentOfTheDeviceLocale() {
        #expect(Formatters.apiDate.locale.identifier == "en_US_POSIX")
        #expect(Formatters.apiDate.date(from: "2026-10-30") != nil)
    }

    @Test func staleAlertsAreThoseThatLeftTheList() {
        func entity(_ id: String) -> AlertEntity {
            AlertEntity(id: id, title: id, message: "", severity: .info, host: "h", date: nil, acknowledged: false)
        }
        let stale = AlertEntityMapper.staleIDs(previous: [entity("a"), entity("b")], current: [entity("b"), entity("c")])
        #expect(stale == ["a"])
        #expect(AlertEntityMapper.staleIDs(previous: [], current: [entity("a")]).isEmpty)
    }

    @Test func focusIsMissingOnlyAfterTheListArrived() {
        #expect(!VisionAlertsView.isFocusMissing(focusedID: "x", loaded: false, triggerIDs: []))
        #expect(VisionAlertsView.isFocusMissing(focusedID: "x", loaded: true, triggerIDs: ["y"]))
        #expect(!VisionAlertsView.isFocusMissing(focusedID: "x", loaded: true, triggerIDs: ["x"]))
        #expect(!VisionAlertsView.isFocusMissing(focusedID: nil, loaded: true, triggerIDs: []))
    }

    @MainActor @Test(.enabled(if: VisionTripItinerary.isAvailable)) func tripIsRefilteredAfterTheReloadInterval() throws {
        let suite = "cleanup.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        final class Box { var now = Date(timeIntervalSince1970: 1_000) }
        let box = Box()
        let writer = WidgetSnapshotWriter(defaults: defaults, minimumReloadInterval: 0,
                                          clock: { box.now }, reloader: {})
        writer.loadTripIfNeeded()
        #expect(!writer.snapshot.tripFlights.isEmpty)

        // Dentro do intervalo nada muda, nem com os voos já no passado.
        box.now = Date(timeIntervalSince1970: 1_000 + WidgetSnapshotWriter.tripReloadInterval - 1)
        writer.loadTripIfNeeded()
        #expect(!writer.snapshot.tripFlights.isEmpty)

        box.now = Date(timeIntervalSinceReferenceDate: 3_000_000_000)
        writer.loadTripIfNeeded()
        #expect(writer.snapshot.tripFlights.isEmpty)
    }

    @Test func failedLookupWinsOverNotFoundButNotOverAPhoto() {
        let photo = VisionAircraftPhoto(url: URL(string: "https://a.test/p.jpg")!, photographer: nil, source: "t")
        #expect(VisionPhotoLookup.failed.merged(with: .found(photo)).photo?.source == "t")
        if case .failed = VisionPhotoLookup.failed.merged(with: .notFound) {} else { Issue.record("falha sumiu") }
        if case .failed = VisionPhotoLookup.notFound.merged(with: .failed) {} else { Issue.record("falha sumiu") }
        if case .notFound = VisionPhotoLookup.notFound.merged(with: .notFound) {} else { Issue.record("virou falha") }
    }

    @Test func enrichmentCacheExpiresAndEvicts() {
        let start = Date(timeIntervalSince1970: 1_000)
        var cache = VisionEnrichmentCache<String?>(limit: 2)
        cache.insert(nil, for: "sem-foto", now: start)
        // "Sem foto" também é resposta em cache: valor externo presente, interno nil.
        #expect(cache.value(for: "sem-foto", now: start) == .some(nil))
        #expect(cache.value(for: "sem-foto", now: start.addingTimeInterval(301)) == nil)

        cache.insert("a", for: "a", now: start.addingTimeInterval(1))
        cache.insert("b", for: "b", now: start.addingTimeInterval(2))
        #expect(cache.count == 2)
        #expect(cache.value(for: "sem-foto", now: start.addingTimeInterval(2)) == nil)

        cache.insert("c", for: "c", now: start.addingTimeInterval(400))
        #expect(cache.count == 1)
        #expect(cache.value(for: "c", now: start.addingTimeInterval(400)) == "c")
    }
}
