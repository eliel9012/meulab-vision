import SwiftUI

/// Rastreia se a janela principal (mission-control) está aberta, para que
/// janelas auxiliares (volume, mapa, busca) nunca fiquem órfãs sem o painel.
@MainActor
@Observable
final class VisionWindowCoordinator {
    private(set) var missionControlCount = 0

    var isMissionControlOpen: Bool { missionControlCount > 0 }

    /// Windows opened with `pushWindow` hide (not close) mission-control;
    /// while one is up, auxiliary windows must not reopen the main panel.
    private(set) var pushedWindowCount = 0

    var hasPushedWindow: Bool { pushedWindowCount > 0 }

    /// Set between `openWindow` and the scene appearing, so several auxiliary windows
    /// waking together don't each open a panel. Expires in case the open never lands.
    @ObservationIgnored private var missionControlClaimedAt: Date?
    static let missionControlClaimTimeout: TimeInterval = 5

    func claimMissionControlOpen(now: Date = Date()) -> Bool {
        guard !isMissionControlOpen, !hasPushedWindow else { return false }
        if let missionControlClaimedAt, now.timeIntervalSince(missionControlClaimedAt) < Self.missionControlClaimTimeout {
            return false
        }
        missionControlClaimedAt = now
        return true
    }

    func missionControlAppeared() {
        missionControlClaimedAt = nil
        missionControlCount += 1
    }
    func missionControlDisappeared() { missionControlCount = max(0, missionControlCount - 1) }
    func pushedWindowAppeared() { pushedWindowCount += 1 }
    func pushedWindowDisappeared() { pushedWindowCount = max(0, pushedWindowCount - 1) }
}

/// Salvaguarda para janelas auxiliares: se aparecerem (ou o app voltar a ficar
/// ativo) sem o mission-control aberto, reabre o painel principal.
private struct EnsureMissionControl: ViewModifier {
    let windows: VisionWindowCoordinator
    @Environment(\.openWindow) private var openWindow
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .task { await ensure() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await ensure() } }
            }
            // Intent/notificação com só janelas auxiliares abertas: o painel
            // principal precisa existir para aplicar a rota.
            .onChange(of: VisionDeepLinkRouter.shared.pending) { _, request in
                if request != nil { Task { await ensure() } }
            }
    }

    private func ensure() async {
        // Dá tempo para o mission-control restaurado/lançado aparecer primeiro.
        try? await Task.sleep(for: .milliseconds(500))
        guard !Task.isCancelled, windows.claimMissionControlOpen() else { return }
        openWindow(id: "mission-control")
    }
}

@main
struct MeuLabVisionApp: App {
    @State private var flights = FlightStore()
    @State private var lab = VisionLabStore()
    @State private var windows = VisionWindowCoordinator()
    @State private var router = VisionDeepLinkRouter.shared
    @State private var immersiveRadar = ImmersiveRadarState.shared

    init() {
        VisionAlertNotifier.shared.configure()
        SpatialAudioSession.configure()
    }

    var body: some Scene {
        WindowGroup(id: "mission-control") {
            VisionRootView()
                .environment(flights)
                .environment(lab)
                .environment(windows)
                .environment(router)
        }
        // Default glass window style (no .plain + custom dark background).
        .defaultSize(width: 1120, height: 850)
        .defaultLaunchBehavior(.presented)
        .handlesExternalEvents(matching: ["*"])

        WindowGroup(id: "radar-volume") {
            RadarVolumeView()
                .environment(flights)
                .modifier(EnsureMissionControl(windows: windows))
        }
        .windowStyle(.volumetric)
        .defaultSize(width: RadarVolumeSize.baseWidth, height: RadarVolumeSize.baseHeight,
                     depth: RadarVolumeSize.baseDepth, in: .meters)
        // Content frame follows the table size setting (RadarVolumeSize).
        // No dynamic world scaling: it enlarges the volume with distance, and the table is sized in real metres.
        .windowResizability(.contentSize)
        .defaultWindowPlacement { _, context in
            guard let control = context.windows.first(where: { $0.id == "mission-control" }) else {
                return WindowPlacement()
            }
            return WindowPlacement(.trailing(control))
        }
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)
        .handlesExternalEvents(matching: [])

        WindowGroup(id: "radar-map") {
            RadarMapWindowView()
                .environment(flights)
                .modifier(EnsureMissionControl(windows: windows))
        }
        .defaultSize(width: 1_050, height: 800)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)
        .handlesExternalEvents(matching: [])

        WindowGroup(id: "flight-search") {
            VisionFlightSearchView()
                .environment(flights)
                .environment(lab)
                .modifier(EnsureMissionControl(windows: windows))
        }
        .defaultSize(width: 940, height: 800)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)
        .handlesExternalEvents(matching: [])

        // Detached Lab section ("Abrir em janela"). Transient: never restored,
        // so relaunch always lands on mission-control.
        WindowGroup(id: "lab-panel", for: VisionSection.self) { $section in
            VisionLabPanelView(section: section)
                .environment(flights)
                .environment(lab)
                .environment(windows)
                .environment(router)
                .modifier(EnsureMissionControl(windows: windows))
        }
        .defaultSize(width: 1_000, height: 780)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)
        .handlesExternalEvents(matching: [])

        // 3D view of a day × hour heatmap (Analytics, ACARS).
        WindowGroup(id: "hour-day-chart", for: HourDayChartData.self) { $data in
            Group {
                if let data {
                    HourDayChart3D(data: data)
                } else {
                    ContentUnavailableView("Gráfico indisponível", systemImage: "cube")
                }
            }
            .modifier(EnsureMissionControl(windows: windows))
        }
        .windowStyle(.volumetric)
        .defaultSize(width: 0.7, height: 0.6, depth: 0.7, in: .meters)
        .defaultWindowPlacement { _, context in
            guard let control = context.windows.first(where: { $0.id == "mission-control" }) else {
                return WindowPlacement()
            }
            return WindowPlacement(.trailing(control))
        }
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)
        .handlesExternalEvents(matching: [])

        // ACARS message detail, opened with pushWindow from VisionACARSView.
        WindowGroup(id: "acars-message", for: Int.self) { $messageID in
            ACARSMessageWindowView(messageID: messageID)
                .onAppear { windows.pushedWindowAppeared() }
                .onDisappear { windows.pushedWindowDisappeared() }
        }
        .defaultSize(width: 760, height: 650)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)
        .handlesExternalEvents(matching: [])

        WindowGroup(id: "docker-logs", for: String.self) { $containerName in
            // Pushed (pushWindow) from the infra view: mission-control is only
            // hidden, so track it instead of re-opening the main window.
            DockerLogsWindowView(containerName: containerName)
                .onAppear { windows.pushedWindowAppeared() }
                .onDisappear { windows.pushedWindowDisappeared() }
        }
        .defaultSize(width: 900, height: 680)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)
        .handlesExternalEvents(matching: [])

        // Fase 5A: radar on a real table / room scale; "seguir avião" switches to progressive.
        ImmersiveSpace(id: ImmersiveRadarState.spaceID) {
            ImmersiveRadarView()
                .environment(flights)
        }
        .immersionStyle(selection: $immersiveRadar.immersionStyle, in: .mixed, .progressive)
    }
}
