import Foundation
import Observation

struct FlightTrackPoint: Sendable {
    let latitude: Double
    let longitude: Double
    let altitudeMeters: Double
    let recordedAt: Date
}

/// View state and polling lifecycle. All observable mutations take place on the main actor.
@MainActor
@Observable
final class FlightStore {
    var aircraft: [Aircraft] = [] {
        didSet { aircraftVersion &+= 1 }
    }
    var selectedHex: String? {
        didSet {
            guard selectedHex != oldValue, !isApplyingSilentSelection else { return }
            hasExplicitSelection = true
            sharePlay.localSelectionChanged(selectedHex)
        }
    }
    var settings = RadarSettings()
    var mapStyle: RadarMapStyle = .standard
    var showAirports = true
    var showTrails = false
    var showClouds = true
    var cloudCapturedAt: Date?
    var cloudError: String?
    var showMapLabels = true
    var followsSelection = false
    var isMapOpen = false
    var isSearchOpen = false
    var tracks: [String: [FlightTrackPoint]] = [:]
    var trackRevision = 0
    var lastReceivedAt: Date?
    var snapshotGeneratedAt: Date?
    var status = "Pronto para conectar"
    var errorMessage: String?
    var isConnected = false
    var isPaused = false
    var isLoading = false
    var isVolumeOpen = false {
        didSet { if isVolumeOpen { volumeOpenRequestedAt = nil } }
    }
    var failureCount = 0

    @ObservationIgnored private let client: any ADSBProviding
    /// SharePlay "Radar MeuLab": syncs `selectedHex` and the volume table transform.
    @ObservationIgnored let sharePlay = RadarSharePlayCoordinator()
    /// Automatic/remote selection changes are not broadcast (anti-echo, no auto-select fights).
    @ObservationIgnored private var isApplyingSilentSelection = false
    /// Someone chose (or cleared) the selection: auto-select must not override it.
    @ObservationIgnored private var hasExplicitSelection = false
    @ObservationIgnored private var volumeOpenRequestedAt: Date?
    @ObservationIgnored private var pollingTask: Task<Void, Never>?
    @ObservationIgnored private var fetching = false
    /// Smallest (local receipt − receiver `now`) gap seen this session: the offset between
    /// this device's clock and the receiver's, plus the best network latency.
    @ObservationIgnored private var clockOffset: TimeInterval?
    /// Bumped whenever `aircraft` is replaced; identifies the snapshot for memoisation.
    @ObservationIgnored private var aircraftVersion = 0
    @ObservationIgnored private var renderableCache: (key: RenderableKey, value: [Aircraft])?
    /// Scenes/windows currently needing live polling (volume, map, search, root…).
    @ObservationIgnored private(set) var pollingClients: Set<String> = []

    private struct RenderableKey: Equatable {
        let version: Int
        let date: Date
        let settings: RadarSettings
    }

    init(client: any ADSBProviding = ADSBClient()) {
        self.client = client
        sharePlay.applySelection = { [weak self] hex in
            self?.hasExplicitSelection = true
            self?.setSelectionSilently(hex)
        }
        sharePlay.currentSelection = { [weak self] in self?.selectedHex }
    }

    /// True once per pending request: `isVolumeOpen` only flips when the scene appears,
    /// so several windows/routes asking in that gap must not stack `openWindow` calls.
    func requestVolumeOpen(now: Date = Date()) -> Bool {
        guard !isVolumeOpen else { return false }
        if let volumeOpenRequestedAt, now.timeIntervalSince(volumeOpenRequestedAt) < Self.volumeOpenTimeout {
            return false
        }
        volumeOpenRequestedAt = now
        return true
    }

    static let volumeOpenTimeout: TimeInterval = 5

    /// Changes the selection without broadcasting it to the SharePlay group.
    func setSelectionSilently(_ hex: String?) {
        isApplyingSilentSelection = true
        defer { isApplyingSilentSelection = false }
        selectedHex = hex
    }

    /// No fresh snapshot is coming (paused or feed down): the radar scenes must re-evaluate
    /// position ages on a timer, or stale aircraft would stay on the table.
    var needsAgeTick: Bool { isPaused || !isConnected }

    var selectedAircraft: Aircraft? { aircraft.first { $0.hex == selectedHex } }
    var receivedCount: Int { aircraft.count }
    var positionedCount: Int { aircraft.filter(\.hasPosition).count }
    var maxAltitudeFeet: Double? { aircraft.compactMap(\.altitudeFeet).max() }
    var maxSpeedKilometersPerHour: Double? { aircraft.compactMap(\.speedKilometersPerHour).max() }

    var filteredAircraft: [Aircraft] {
        switch settings.filter {
        case .all: return aircraft
        case .positioned: return aircraft.filter(\.hasPosition)
        case .withoutPosition: return aircraft.filter { !$0.hasPosition }
        }
    }

    func ageOfPosition(_ flight: Aircraft, at now: Date) -> Double? {
        guard let original = flight.seenPositionSeconds else { return nil }
        // readsb ages count from the receiver's `now`; shift it onto this device's clock so
        // a clock difference neither hides live traffic nor makes stale traffic look fresh.
        let anchor = snapshotGeneratedAt?.addingTimeInterval(clockOffset ?? 0) ?? lastReceivedAt ?? now
        return original + max(0, now.timeIntervalSince(anchor))
    }

    /// Position age by hex, as the radar scenes need it. A repeated hex keeps its last value.
    func positionAges(at now: Date) -> [String: Double] {
        Dictionary(aircraft.compactMap { flight in
            ageOfPosition(flight, at: now).map { (flight.hex, $0) }
        }, uniquingKeysWith: { _, last in last })
    }

    func isRenderable(_ flight: Aircraft, at now: Date) -> Bool {
        guard flight.hasPosition,
              let lat = flight.latitude, let lon = flight.longitude,
              let age = ageOfPosition(flight, at: now), age <= settings.maxPositionAgeSeconds,
              let altitude = flight.altitudeFeet, altitude >= settings.minimumAltitudeFeet else { return false }
        let enu = Geodesy.enu(.init(latitudeDegrees: lat, longitudeDegrees: lon, altitudeMeters: flight.geometricAltitudeMeters ?? flight.altitudeMeters ?? 0), relativeTo: Geodesy.approximateFranca)
        return enu.horizontalDistanceMeters <= settings.displayRadiusKilometers * 1000
    }

    /// Memoised per (snapshot version, date, settings): the radar volume asks for the
    /// same list several times per update (scene, labels, attachments).
    func renderableAircraft(at now: Date = Date()) -> [Aircraft] {
        // Touch observed properties so callers keep tracking them on cache hits.
        let flights = aircraft
        let key = RenderableKey(version: aircraftVersion, date: now, settings: settings)
        if let cached = renderableCache, cached.key == key { return cached.value }
        let value = flights.filter { isRenderable($0, at: now) }
        renderableCache = (key, value)
        return value
    }

    /// Legacy entry point (main window). Equivalent to `acquirePolling("root")`.
    func start() {
        acquirePolling("root")
    }

    /// Reference-counted polling: each scene registers a client id while visible and
    /// releases it when it goes away. Polling stops only when no client remains.
    func acquirePolling(_ client: String) {
        pollingClients.insert(client)
        if !isPaused { startPolling() }
    }

    func releasePolling(_ client: String) {
        pollingClients.remove(client)
        if pollingClients.isEmpty { stopPolling() }
    }

    func setPaused(_ paused: Bool) {
        isPaused = paused
        if paused {
            stopPolling()
            status = "Atualizações pausadas"
        } else if !pollingClients.isEmpty {
            startPolling()
        }
    }

    func startPolling() {
        guard !isPaused, pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled, !self.isPaused {
                await self.refresh()
                let retry = min(60.0, 3.0 * pow(2.0, Double(min(self.failureCount, 5))))
                do { try await Task.sleep(for: .seconds(retry)) }
                catch { break }
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func refresh() async {
        guard !fetching else { return }
        fetching = true
        isLoading = true
        defer { fetching = false; isLoading = false }
        if !isConnected {
            status = "Atualizando radar…"
        }
        do {
            let data = try await client.fetch()
            let snapshot = try await Task.detached(priority: .userInitiated) {
                try AircraftDecoder.decode(data)
            }.value
            guard !Task.isCancelled else { return }
            apply(snapshot)
            failureCount = 0
            isConnected = true
            errorMessage = nil
            status = "Conectado ao radar ADS-B"
        } catch {
            guard !Task.isCancelled else { return }
            failureCount += 1
            isConnected = false
            errorMessage = error.localizedDescription
            status = "Falha ao atualizar radar"
            // Keep previous actual observations, clearly marked disconnected.
        }
    }

    private func apply(_ snapshot: AircraftSnapshot) {
        let receivedAt = Date()
        if let generatedAt = snapshot.generatedAt {
            // A receiver that stops updating keeps its old `now`: the gap only grows, the
            // minimum stays, and its aircraft still age out.
            let gap = receivedAt.timeIntervalSince(generatedAt)
            clockOffset = min(clockOffset ?? gap, gap)
        }
        aircraft = snapshot.aircraft
        lastReceivedAt = receivedAt
        snapshotGeneratedAt = snapshot.generatedAt
        recordTracks(at: receivedAt)
        WidgetSnapshotWriter.shared.updateRadar(aircraftCount: aircraft.count, positionedCount: positionedCount)
        // In a SharePlay group the hex may come from a participant whose feed differs:
        // keep it pending instead of clearing it for this participant.
        if let selectedHex, !sharePlay.isActive, !aircraft.contains(where: { $0.hex == selectedHex }) {
            setSelectionSilently(nil)
        }
        if selectedHex == nil, !hasExplicitSelection {
            setSelectionSilently(aircraft.first(where: { isRenderable($0, at: Date()) })?.hex)
        }
        errorMessage = nil
    }

    private func recordTracks(at now: Date) {
        var changed = false
        for flight in aircraft {
            guard let lat = flight.latitude, let lon = flight.longitude,
                  (flight.seenPositionSeconds ?? .infinity) <= 30 else { continue }
            if let previous = tracks[flight.hex]?.last {
                guard now.timeIntervalSince(previous.recordedAt) >= 10,
                      abs(lat - previous.latitude) > 0.0001 || abs(lon - previous.longitude) > 0.0001 else { continue }
            }
            let point = FlightTrackPoint(latitude: lat, longitude: lon,
                                         altitudeMeters: flight.altitudeMeters ?? 0, recordedAt: now)
            var history = tracks[flight.hex] ?? []
            history.append(point)
            tracks[flight.hex] = Array(history.suffix(120))
            changed = true
        }
        for hex in Array(tracks.keys) {
            let recent = tracks[hex, default: []].filter { now.timeIntervalSince($0.recordedAt) < 1_800 }
            if recent.count != tracks[hex]?.count {
                changed = true
                if recent.isEmpty { tracks.removeValue(forKey: hex) }
                else { tracks[hex] = recent }
            }
        }
        if changed { trackRevision += 1 }
    }
}
