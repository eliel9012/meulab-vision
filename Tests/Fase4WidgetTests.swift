import Foundation
import Testing
@testable import MeuLabVision

@Suite("Fase 4 · Widgets")
struct Fase4WidgetTests {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

    private func sample(now: Date) -> WidgetSnapshot {
        WidgetSnapshot(
            system: .init(hostname: "radar", cpuPercent: 42.6, memoryPercent: 51, diskPercent: 70.2, temperatureC: 55.4),
            alerts: .init(pendingCount: 3, latestMessage: "Disco acima de 70%"),
            radar: .init(aircraftCount: 28, positionedCount: 21),
            tripFlights: [
                .init(id: "a", code: "G3 9405", originCode: "RAO", destinationCode: "GRU",
                      departure: now.addingTimeInterval(-7_200)),
                .init(id: "b", code: "UX 9158", originCode: "GRU", destinationCode: "MAD",
                      departure: now.addingTimeInterval(86_400 * 3))
            ],
            updatedAt: now)
    }

    @Test func snapshotRoundTripsThroughDefaults() throws {
        let suite = "fase4.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = sample(now: now)
        snapshot.save(to: defaults)
        #expect(WidgetSnapshot.load(from: defaults) == snapshot)

        let data = try WidgetSnapshot.encoder.encode(snapshot)
        #expect(try WidgetSnapshot.decoder.decode(WidgetSnapshot.self, from: data) == snapshot)
    }

    @Test func missingSnapshotLoadsNil() throws {
        let suite = "fase4.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        #expect(WidgetSnapshot.load(from: defaults) == nil)
    }

    @Test func deepLinksUseSectionCaseNames() {
        #expect(WidgetDeepLink.system.url.absoluteString == "meulabvision://section/system")
        #expect(WidgetDeepLink.radar.url.absoluteString == "meulabvision://section/radar")
        let sectionNames = Set(["radar", "system", "alerts", "trip"])
        #expect(Set(WidgetDeepLink.allCases.map(\.rawValue)) == sectionNames)
        // Cada id corresponde a um case de VisionSection.
        let cases: [VisionSection] = [.radar, .system, .alerts, .trip]
        #expect(Set(cases.map { "\($0)" }) == sectionNames)
    }

    @Test func levelOfDetailSelection() {
        #expect(WidgetDetail(isSimplified: true) == .glanceable)
        #expect(WidgetDetail(isSimplified: false) == .detailed)
    }

    @Test func systemContentFarShowsOneNumberNearShowsDetail() {
        let snapshot = sample(now: Date())
        let far = WidgetContent.system(snapshot, detail: .glanceable)
        #expect(far.headline == "43%")
        #expect(far.lines.isEmpty)
        let near = WidgetContent.system(snapshot, detail: .detailed)
        #expect(near.lines == ["CPU 43%", "RAM 51%", "Disco 70%", "Temp 55°C"])
        #expect(WidgetContent.system(nil, detail: .glanceable).headline == "—")
    }

    @Test func alertsAndRadarContent() {
        let snapshot = sample(now: Date())
        #expect(WidgetContent.alerts(snapshot, detail: .glanceable) == .init(headline: "3", caption: "Alertas", lines: []))
        #expect(WidgetContent.alerts(snapshot, detail: .detailed).lines == ["Disco acima de 70%"])
        var clear = snapshot
        clear.alerts = .init(pendingCount: 0, latestMessage: nil)
        #expect(WidgetContent.alerts(clear, detail: .detailed).lines == ["Tudo reconhecido"])
        #expect(WidgetContent.radar(snapshot, detail: .glanceable).headline == "28")
        #expect(WidgetContent.radar(snapshot, detail: .detailed).lines == ["21 com posição"])
    }

    @Test func tripPicksNextFlightAndCountsDays() {
        let now = date("2026-11-01T12:00:00Z")
        let snapshot = sample(now: now)
        #expect(snapshot.nextFlight(after: now)?.id == "b")
        let near = WidgetContent.trip(snapshot, now: now, detail: .detailed, calendar: utc)
        #expect(near.headline == "3d")
        #expect(near.caption == "faltam 3 dias")
        #expect(near.lines == ["UX 9158", "GRU → MAD"])
        #expect(WidgetContent.trip(snapshot, now: now, detail: .glanceable, calendar: utc).lines.isEmpty)
        let after = WidgetContent.trip(snapshot, now: now.addingTimeInterval(86_400 * 5), detail: .detailed, calendar: utc)
        #expect(after.caption == "Sem voos")
        #expect(WidgetContent.daysUntil(date("2026-11-01T23:00:00Z"), from: now, calendar: utc) == 0)
    }

    @Test func throttleAllowsOneReloadPerInterval() {
        var throttle = WidgetReloadThrottle(minimumInterval: 60)
        let start = Date(timeIntervalSince1970: 0)
        let results = [0.0, 30, 60, 61].map { throttle.shouldReload(at: start.addingTimeInterval($0)) }
        #expect(results == [true, false, true, false])
        #expect(throttle.remaining(at: start.addingTimeInterval(90)) == 30)
    }

    @MainActor @Test func writerPersistsAndThrottlesReloads() throws {
        let suite = "fase4.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        final class Box { var now = Date(timeIntervalSince1970: 1_000); var reloads = 0 }
        let box = Box()
        let writer = WidgetSnapshotWriter(defaults: defaults, minimumReloadInterval: 3_600,
                                          clock: { box.now }, reloader: { box.reloads += 1 })
        writer.updateRadar(aircraftCount: 10, positionedCount: 8)
        #expect(box.reloads == 1)
        #expect(WidgetSnapshot.load(from: defaults)?.radar == .init(aircraftCount: 10, positionedCount: 8))

        box.now += 5
        writer.updateRadar(aircraftCount: 10, positionedCount: 8) // sem mudança: nada
        writer.updateRadar(aircraftCount: 12, positionedCount: 9) // muda, mas dentro do intervalo
        #expect(box.reloads == 1)
        #expect(WidgetSnapshot.load(from: defaults)?.radar?.aircraftCount == 12)

        box.now += 3_600
        writer.updateRadar(aircraftCount: 14, positionedCount: 9)
        #expect(box.reloads == 2)
    }
}
