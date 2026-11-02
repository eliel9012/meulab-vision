import Foundation

/// One fetch per key, shared by every caller. A result stays valid for `lifetime`;
/// a failure is dropped so the next caller tries again.
@MainActor
final class RadarSharedFetch<Key: Equatable, Value: Sendable> {
    private let lifetime: TimeInterval
    private var key: Key?
    private var task: Task<Value, Error>?
    private var startedAt = Date.distantPast

    init(lifetime: TimeInterval) {
        self.lifetime = lifetime
    }

    func value(for key: Key, now: Date = Date(),
               fetch: @escaping @MainActor () async throws -> Value) async throws -> Value {
        if key != self.key || now.timeIntervalSince(startedAt) >= lifetime {
            task?.cancel()
            task = nil
        }
        if let task { return try await task.value }
        let task = Task { try await fetch() }
        self.key = key
        self.task = task
        startedAt = now
        do {
            return try await task.value
        } catch {
            if self.task == task { self.task = nil }
            throw error
        }
    }
}

enum RadarRetry {
    /// Repeats `operation` until it succeeds. Returns nil only when the task is cancelled.
    @MainActor
    static func untilSuccess<Value>(delay: Duration,
                                    operation: @MainActor () async throws -> Value) async -> Value? {
        while !Task.isCancelled {
            do {
                let value = try await operation()
                return Task.isCancelled ? nil : value
            } catch {
                try? await Task.sleep(for: delay)
            }
        }
        return nil
    }
}

/// Map and cloud surfaces of one radar scene (volume or immersive). The downloads are
/// shared, so having both scenes open does not fetch anything twice.
@MainActor
@Observable
final class RadarSurfaceFeed {
    private(set) var mapSurface: RadarMapSurface?
    private(set) var mapRevision = 0
    private(set) var cloudSurface: RadarCloudSurface?
    private(set) var cloudRevision = 0

    private struct MapKey: Equatable {
        let radiusKilometers: Double
        let style: RadarMapStyle
    }

    private static let maps = RadarSharedFetch<MapKey, RadarMapSurface>(lifetime: 24 * 60 * 60)
    /// Shorter than `cloudRefresh`, so every refresh gets a new image.
    private static let clouds = RadarSharedFetch<Double, RadarCloudSurface>(lifetime: 5 * 60)
    private static let mapRetry = Duration.seconds(60)
    private static let cloudRefresh = Duration.seconds(600)
    private static let cloudRetry = Duration.seconds(120)

    /// Run inside `.task(id:)`; the previous surface never outlives the radius it was drawn for.
    func loadMap(radiusKilometers: Double, style: RadarMapStyle) async {
        setMap(nil)
        // Real DEM relief and radar grid remain available if MapKit cannot load.
        let key = MapKey(radiusKilometers: radiusKilometers, style: style)
        let surface = await RadarRetry.untilSuccess(delay: Self.mapRetry) {
            try await Self.maps.value(for: key) {
                try await RadarMapSnapshot.surface(radiusKilometers: radiusKilometers, style: style)
            }
        }
        if let surface { setMap(surface) }
    }

    /// Run inside `.task(id:)`; keeps the cloud layer fresh until cancelled.
    func loadClouds(radiusKilometers: Double, enabled: Bool, store: FlightStore) async {
        setClouds(nil)
        store.cloudCapturedAt = nil
        store.cloudError = nil
        guard enabled else { return }
        while !Task.isCancelled {
            do {
                let surface = try await Self.clouds.value(for: radiusKilometers) {
                    try await RadarCloudSnapshot.surface(radiusKilometers: radiusKilometers)
                }
                guard !Task.isCancelled else { return }
                setClouds(surface)
                store.cloudCapturedAt = surface.capturedAt
                store.cloudError = nil
                try await Task.sleep(for: Self.cloudRefresh)
            } catch {
                guard !Task.isCancelled else { return }
                setClouds(nil)
                store.cloudCapturedAt = nil
                store.cloudError = error.localizedDescription
                try? await Task.sleep(for: Self.cloudRetry)
            }
        }
    }

    private func setMap(_ surface: RadarMapSurface?) {
        mapSurface = surface
        mapRevision += 1
    }

    private func setClouds(_ surface: RadarCloudSurface?) {
        cloudSurface = surface
        cloudRevision += 1
    }
}
