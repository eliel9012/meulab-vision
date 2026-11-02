import AVFoundation
import Foundation
import Observation

/// `rawValue` é persistido (`@SceneStorage`, valor de janela): usa o nome do case,
/// e o texto mostrado fica em `title`, livre para mudar.
enum VisionSection: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case radar, trip, analytics, alerts, system, infrastructure, radio, weather, acars, series

    var id: String { rawValue }
    var title: String {
        switch self {
        case .radar: "ADS-B"
        case .trip: "Viagem"
        case .analytics: "Analytics"
        case .alerts: "Alertas"
        case .system: "Sistema"
        case .infrastructure: "Infraestrutura"
        case .radio: "Rádio"
        case .weather: "Clima"
        case .acars: "ACARS"
        case .series: "Séries"
        }
    }
    var symbol: String {
        switch self {
        case .radar: "airplane"
        case .trip: "suitcase.rolling.fill"
        case .analytics: "chart.xyaxis.line"
        case .alerts: "bell.badge"
        case .system: "cpu"
        case .infrastructure: "server.rack"
        case .radio: "radio"
        case .weather: "cloud.sun"
        case .acars: "waveform.path"
        case .series: "film.stack"
        }
    }

    /// The tab bar only exposes 8 items and drops the rest, so these sections
    /// share a tab with a sibling and switch through a picker inside it.
    var tabHost: VisionSection {
        switch self {
        case .infrastructure: .system
        case .series: .radio
        default: self
        }
    }
    /// Sections reachable from this tab's picker; empty when it holds only one.
    var tabSiblings: [VisionSection] {
        switch tabHost {
        case .system: [.system, .infrastructure]
        case .radio: [.radio, .series]
        default: []
        }
    }
    var tabTitle: String { self == .radio ? "Mídia" : title }
    var tabSymbol: String { self == .radio ? "play.rectangle.on.rectangle" : symbol }
    static var tabs: [VisionSection] { allCases.filter { $0.tabHost == $0 } }
}

@MainActor @Observable
final class VisionLabStore {
    var selection: VisionSection = .radar
    var system: SystemStatus?
    var processes: [VisionProcess] = []
    var partitions: [VisionPartition] = []
    var interfaces: [VisionNetworkInterface] = []
    var radio: NowPlaying?
    var radioHistory: [NowPlaying] = []
    var weather: WeatherData?
    var acars: VisionACARSSummary?
    var acarsMessages: [VisionACARSMessage] = []
    /// Per section: a failure or a refresh in one panel must not show up in another.
    private(set) var errors: [VisionSection: String] = [:]
    private(set) var updatedAts: [VisionSection: Date] = [:]
    private var loadingCounts: [VisionSection: Int] = [:]
    var isPlaying = false
    var radioError: String?

    @ObservationIgnored private var pollTask: Task<Void, Never>?
    /// Windows currently needing polling; it stops only when none remains.
    @ObservationIgnored private(set) var pollingClients: Set<String> = []
    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var playerObservations: [NSKeyValueObservation] = []
    /// Identifies the current player: late KVO hops from a replaced one are dropped.
    @ObservationIgnored private var playerGeneration = 0
    @ObservationIgnored private var widgetRefreshedAt: Date?
    /// Intervalo mínimo entre buscas extras de sistema/alertas só para os widgets.
    static let widgetRefreshInterval: TimeInterval = 120

    func isLoading(_ section: VisionSection) -> Bool { (loadingCounts[section] ?? 0) > 0 }

    func acquirePolling(_ client: String) {
        pollingClients.insert(client)
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.refresh()
                await self.refreshWidgetData()
                do { try await Task.sleep(for: .seconds(20)) }
                catch { break }
            }
        }
    }

    func releasePolling(_ client: String) {
        pollingClients.remove(client)
        guard pollingClients.isEmpty else { return }
        pollTask?.cancel()
        pollTask = nil
    }

    func select(_ section: VisionSection) {
        selection = section
        Task { await refresh() }
    }

    func refresh() async { await refresh(selection) }

    /// Sections whose data lives in this store (the rest poll on their own).
    static func usesStoreData(_ section: VisionSection) -> Bool {
        switch section {
        case .system, .infrastructure, .radio: true
        default: false
        }
    }

    /// Refreshes one section; also used by detached `lab-panel` windows.
    func refresh(_ selection: VisionSection) async {
        guard Self.usesStoreData(selection) else { return }
        loadingCounts[selection, default: 0] += 1
        defer { loadingCounts[selection, default: 1] -= 1 }
        do {
            let api = try VisionAPIClient.shared
            switch selection {
            case .system:
                system = try await api.fetch("api/system/status")
                if let system { WidgetSnapshotWriter.shared.updateSystem(system) }
            case .infrastructure:
                async let status: SystemStatus = api.fetch("api/system/status")
                async let processList: VisionProcessList = api.fetch("api/system/processes?limit=8")
                async let partitionList: VisionPartitionList = api.fetch("api/system/partitions")
                async let network: VisionNetworkStats = api.fetch("api/system/network")
                (system, processes, partitions, interfaces) = try await (status, processList.items, partitionList.partitions, network.interfaces)
                if let system { WidgetSnapshotWriter.shared.updateSystem(system) }
            case .radio:
                async let now: NowPlaying = api.fetch("api/radio/now-playing")
                async let history: RadioHistoryResponse = api.fetch("api/radio/history?limit=40")
                (radio, radioHistory) = try await (now, history.items)
            default:
                break // Barrado por `usesStoreData`.
            }
            errors[selection] = nil
            updatedAts[selection] = Date()
        } catch {
            errors[selection] = error.localizedDescription
        }
    }

    /// Busca leve de sistema + alertas para o snapshot dos widgets (no máx. a cada 2 min).
    func refreshWidgetData(now: Date = Date()) async {
        if let widgetRefreshedAt, now.timeIntervalSince(widgetRefreshedAt) < Self.widgetRefreshInterval { return }
        widgetRefreshedAt = now
        let writer = WidgetSnapshotWriter.shared
        writer.loadTripIfNeeded()
        guard let api = try? VisionAPIClient.shared else { return }
        if let status: SystemStatus = try? await api.fetch("api/system/status") {
            writer.updateSystem(status)
        }
        if let triggers: [VisionAlertTrigger] = try? await api.fetch(
            "api/alerts/triggers", query: [URLQueryItem(name: "limit", value: "40")]) {
            writer.updateAlerts(triggers)
        }
    }

    func toggleRadio() {
        if isPlaying {
            player?.pause()
            isPlaying = false
            return
        }
        guard let stream = radio?.streamUrl, let url = URL(string: stream) else {
            radioError = "Stream da rádio indisponível."
            return
        }
        radioError = nil
        let player = AVPlayer(url: url)
        self.player = player
        playerGeneration &+= 1
        playerObservations = Self.observe(player, generation: playerGeneration, store: self)
        player.play()
        isPlaying = true
    }

    /// Nonisolated on purpose: a closure formed in main-actor code would inherit the
    /// isolation and trap if KVO ever fired on another thread.
    nonisolated private static func observe(_ player: AVPlayer, generation: Int, store: VisionLabStore) -> [NSKeyValueObservation] {
        let statusChange = player.observe(\.timeControlStatus, options: [.new]) { [weak store] player, _ in
            let status = player.timeControlStatus
            Task { @MainActor in store?.playerChanged(generation: generation, status: status) }
        }
        guard let item = player.currentItem else { return [statusChange] }
        let itemChange = item.observe(\.status, options: [.new]) { [weak store] item, _ in
            guard item.status == .failed else { return }
            let message = item.error?.localizedDescription
            Task { @MainActor in store?.playerFailed(generation: generation, message: message) }
        }
        return [statusChange, itemChange]
    }

    /// `.waitingToPlayAtSpecifiedRate` is buffering, still "playing" for the button.
    private func playerChanged(generation: Int, status: AVPlayer.TimeControlStatus) {
        guard generation == playerGeneration, status == .paused else { return }
        isPlaying = false
    }

    private func playerFailed(generation: Int, message: String?) {
        guard generation == playerGeneration else { return }
        isPlaying = false
        radioError = message ?? "Não foi possível tocar a rádio."
    }
}
