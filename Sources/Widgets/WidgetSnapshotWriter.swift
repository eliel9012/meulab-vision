import Foundation
import WidgetKit

/// Grava `WidgetSnapshot` no App Group e recarrega as timelines com throttle.
@MainActor
final class WidgetSnapshotWriter {
    static let shared = WidgetSnapshotWriter()

    private(set) var snapshot: WidgetSnapshot
    private var throttle: WidgetReloadThrottle
    private var trailingReload: Task<Void, Never>?
    private let defaults: UserDefaults?
    private let clock: () -> Date
    private let reloader: () -> Void
    private var tripLoadedAt: Date?
    /// Voos que já passaram saem do widget mesmo com o app aberto por dias.
    static let tripReloadInterval: TimeInterval = 3_600

    init(defaults: UserDefaults? = WidgetSnapshot.sharedDefaults,
         minimumReloadInterval: TimeInterval = 60,
         clock: @escaping () -> Date = Date.init,
         reloader: @escaping () -> Void = { WidgetCenter.shared.reloadAllTimelines() }) {
        self.defaults = defaults
        self.clock = clock
        self.reloader = reloader
        throttle = WidgetReloadThrottle(minimumInterval: minimumReloadInterval)
        snapshot = WidgetSnapshot.load(from: defaults) ?? WidgetSnapshot(updatedAt: clock())
    }

    func updateSystem(_ status: SystemStatus) {
        mutate {
            $0.system = .init(hostname: status.hostname,
                              cpuPercent: status.cpu?.usagePercent,
                              memoryPercent: status.memory?.usedPercent,
                              diskPercent: status.disk?.usedPercent,
                              temperatureC: status.cpu?.temperatureC)
        }
    }

    func updateAlerts(_ triggers: [VisionAlertTrigger]) {
        let pending = triggers.filter { !$0.acknowledged }
        mutate { $0.alerts = .init(pendingCount: pending.count, latestMessage: pending.first?.message) }
    }

    func updateRadar(aircraftCount: Int, positionedCount: Int) {
        mutate { $0.radar = .init(aircraftCount: aircraftCount, positionedCount: positionedCount) }
    }

    func updateTrip(_ flights: [VisionTripFlight]) {
        let now = clock()
        tripLoadedAt = now
        let upcoming = flights
            .filter { $0.departure.addingTimeInterval(3_600) >= now }
            .prefix(6)
            .map { WidgetSnapshot.TripFlight(id: $0.id, code: $0.displayCode, originCode: $0.originCode,
                                             destinationCode: $0.destinationCode, departure: $0.departure) }
        mutate { $0.tripFlights = Array(upcoming) }
    }

    /// Carrega o roteiro embutido, no máximo uma vez por `tripReloadInterval`.
    func loadTripIfNeeded() {
        let now = clock()
        if let tripLoadedAt, now.timeIntervalSince(tripLoadedAt) < Self.tripReloadInterval { return }
        tripLoadedAt = now
        guard let days = try? VisionTripItinerary.load() else { return }
        updateTrip(VisionTripFlight.flights(in: days))
    }

    private func mutate(_ change: (inout WidgetSnapshot) -> Void) {
        var next = snapshot
        change(&next)
        var comparable = next
        comparable.updatedAt = snapshot.updatedAt
        guard comparable != snapshot else { return }
        next.updatedAt = clock()
        snapshot = next
        next.save(to: defaults)
        requestReload()
    }

    private func requestReload() {
        let now = clock()
        if throttle.shouldReload(at: now) {
            trailingReload?.cancel()
            trailingReload = nil
            reloader()
            return
        }
        // Garante que a última mudança chegue ao widget quando o intervalo vencer.
        guard trailingReload == nil else { return }
        let delay = throttle.remaining(at: now)
        trailingReload = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.trailingReload = nil
            if self.throttle.shouldReload(at: self.clock()) { self.reloader() }
        }
    }
}
