import SwiftUI

struct VisionRootView: View {
    @Environment(VisionLabStore.self) private var lab
    @Environment(FlightStore.self) private var flights
    @Environment(VisionWindowCoordinator.self) private var windows
    @Environment(VisionDeepLinkRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openWindow) private var openWindow
    /// Per-scene memory of the selected section (restored on relaunch).
    @SceneStorage("lab.section") private var storedSection: VisionSection = .radar
    /// Per window: another mission-control going away must not stop this one's polling.
    @State private var pollingClient = "root-\(UUID().uuidString)"

    private var selection: Binding<VisionSection> {
        Binding(
            get: { lab.selection.tabHost },
            set: { section in
                // Tapping the current tab keeps its picker choice.
                guard section != lab.selection.tabHost else { return }
                lab.select(section)
            }
        )
    }

    var body: some View {
        TabView(selection: selection) {
            ForEach(VisionSection.tabs) { section in
                Tab(section.tabTitle, systemImage: section.tabSymbol, value: section) {
                    VisionTabContent(host: section)
                        .padding(24)
                }
                .contextMenu {
                    Button("Abrir em janela", systemImage: "macwindow.badge.plus") {
                        openWindow(value: section)
                    }
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        // AsyncImage (artwork da rádio, fotos, clima) com URLCache em disco dedicado.
        .visionImageCache()
        .toolbar {
            ToolbarItem(placement: .bottomOrnament) {
                Button("Abrir em janela", systemImage: "macwindow.badge.plus") {
                    openWindow(value: lab.selection)
                }
                .help("Abrir \(lab.selection.title) em uma janela separada")
            }
        }
        .onAppear {
            windows.missionControlAppeared()
            if storedSection != lab.selection { lab.select(storedSection) }
            // Rota pendente (intent/URL/notificação antes da janela existir) vence a restauração.
            apply(router.pending)
        }
        .onOpenURL { url in router.handle(url) }
        .onChange(of: router.pending) { _, request in apply(request) }
        // Poll leve de alertas enquanto ativo → notificações locais de deltas.
        .polling(every: .seconds(60)) { await VisionAlertNotifier.shared.poll() }
        .onDisappear {
            windows.missionControlDisappeared()
            lab.releasePolling(pollingClient)
            flights.releasePolling(pollingClient)
        }
        .task {
            // Here, not in the volume: joining a session must work before it opens.
            flights.sharePlay.startObservingSessions()
            lab.acquirePolling(pollingClient)
            flights.acquirePolling(pollingClient)
            try? await Task.sleep(for: .milliseconds(400))
            if !Task.isCancelled, lab.selection == .radar, flights.requestVolumeOpen() {
                openWindow(id: "radar-volume")
            }
        }
        .onChange(of: lab.selection) { _, section in
            storedSection = section
            // Só abre o volume ao entrar no radar; trocar de seção não fecha
            // janelas auxiliares que o usuário já posicionou.
            if section == .radar, flights.requestVolumeOpen() { openWindow(id: "radar-volume") }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                lab.acquirePolling(pollingClient)
                flights.acquirePolling(pollingClient)
            } else {
                lab.releasePolling(pollingClient)
                flights.releasePolling(pollingClient)
            }
        }
    }

    /// Aplica uma rota externa: seleciona a seção (o `onChange` de seleção abre
    /// o volume ao entrar no radar) ou, se já está no radar, garante o volume.
    private func apply(_ request: VisionRouteRequest?) {
        guard let request else { return }
        router.consume(request)
        if lab.selection != request.section {
            lab.select(request.section)
        } else if request.section == .radar, flights.requestVolumeOpen() {
            openWindow(id: "radar-volume")
        }
    }
}

/// Content of one tab: the section itself, or a picker over the sections sharing it.
private struct VisionTabContent: View {
    @Environment(VisionLabStore.self) private var lab
    let host: VisionSection

    private var visible: VisionSection { lab.selection.tabHost == host ? lab.selection : host }

    var body: some View {
        VisionSectionContent(section: visible)
            .safeAreaInset(edge: .top, spacing: 0) {
                if !host.tabSiblings.isEmpty {
                    Picker("Seção", selection: Binding(get: { visible }, set: { lab.select($0) })) {
                        ForEach(host.tabSiblings) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 380)
                }
            }
    }
}

extension NowPlaying {
    /// Estável entre atualizações: a posição muda a cada música nova na lista.
    var historyID: String { "\(timestamp)|\(title)" }
}

struct VisionDataView: View {
    @Environment(VisionLabStore.self) private var lab
    let section: VisionSection
    var pollsOwnData = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label(section.title, systemImage: section.symbol)
                    .font(.largeTitle.bold())
                Spacer()
                if lab.isLoading(section) { ProgressView() }
            }
            if let error = lab.errors[section] {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .padding(12)
                    .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch section {
                    case .system: systemContent
                    case .infrastructure: infrastructureContent
                    case .radio: radioContent
                    // As demais têm views próprias (ver VisionSectionContent).
                    default: EmptyView()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let time = lab.updatedAts[section] {
                Text("Atualizado \(time.formatted(date: .omitted, time: .standard)) · MeuLab API")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(32)
        .toolbar {
            ToolbarItem(placement: .bottomOrnament) {
                Button("Atualizar", systemImage: "arrow.clockwise") { Task { await lab.refresh(section) } }
            }
        }
        .modifier(SectionSelfPolling(enabled: pollsOwnData, section: section))
    }

    /// Sistema = resumo + extras (histórico/Firestick, com polling próprio).
    private var systemContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            systemSummary
            VisionSystemExtrasView()
        }
    }

    /// Resumo estático de `lab.system` (sem polling próprio).
    private var systemSummary: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let system = lab.system {
                HStack(spacing: 16) {
                    metric("CPU", value: system.cpu?.usagePercent.map { "\(Int($0))%" } ?? "—", symbol: "cpu")
                    metric("Memória", value: system.memory?.usedPercent.map { "\(Int($0))%" } ?? "—", symbol: "memorychip")
                    metric("Disco", value: system.disk?.usedPercent.map { "\(Int($0))%" } ?? "—", symbol: "internaldrive")
                    metric("Temperatura", value: system.cpu?.temperatureC.map { "\(Int($0))°C" } ?? "—", symbol: "thermometer")
                }
                detail("Host", system.hostname)
                detail("Local", system.location)
                detail("Uptime", system.uptime?.formatted ?? "—")
                if let ssid = system.wifi?.ssid { detail("Wi-Fi", ssid) }
            } else { placeholder }
        }
    }

    private var infrastructureContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Processos").font(.title2.bold())
            ForEach(lab.processes) { item in
                detail(item.command, "PID \(item.pid) · CPU \(item.cpuPercent.formatted(.number.precision(.fractionLength(1))))% · RAM \(item.memPercent.formatted(.number.precision(.fractionLength(1))))%")
            }
            Text("Partições").font(.title2.bold())
            ForEach(lab.partitions) { item in detail(item.mount, "\(item.filesystem) · \(item.usedPercent) usado") }
            Text("Rede").font(.title2.bold())
            ForEach(lab.interfaces) { item in detail(item.iface, "↓ \(ByteCountFormatter.string(fromByteCount: item.rxBytes, countStyle: .file)) · ↑ \(ByteCountFormatter.string(fromByteCount: item.txBytes, countStyle: .file))") }
            VisionInfraExtrasView()
        }
    }

    private var radioContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let radio = lab.radio {
                HStack(spacing: 26) {
                    if let artwork = radio.artworkURL {
                        AsyncImage(url: artwork) { image in image.resizable().scaledToFill() } placeholder: { Color.blue.opacity(0.2) }
                            .frame(width: 160, height: 160).clipShape(RoundedRectangle(cornerRadius: 22))
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text(radio.radioName).font(.title3).foregroundStyle(.secondary)
                        Text(radio.title).font(.largeTitle.bold())
                        Text(radio.artist).font(.title2)
                        Button(lab.isPlaying ? "Pausar" : "Ouvir ao vivo", systemImage: lab.isPlaying ? "pause.fill" : "play.fill") { lab.toggleRadio() }
                            .buttonStyle(.borderedProminent)
                        if let radioError = lab.radioError {
                            Label(radioError, systemImage: "exclamationmark.triangle")
                                .font(.callout)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            } else { placeholder }
            Text("Histórico recente").font(.title2.bold())
            if lab.radioHistory.isEmpty {
                Text("Sem músicas recentes registradas.").foregroundStyle(.secondary)
            } else {
                ForEach(lab.radioHistory, id: \.historyID) { track in
                    HStack(spacing: 14) {
                        if let artwork = track.artworkURL {
                            AsyncImage(url: artwork) { image in image.resizable().scaledToFill() }
                                placeholder: { Color.blue.opacity(0.2) }
                                .frame(width: 52, height: 52)
                                .clipShape(RoundedRectangle(cornerRadius: 9))
                        } else {
                            Image(systemName: "music.note")
                                .frame(width: 52, height: 52)
                                .accessibilityHidden(true)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(track.title).font(.headline)
                            Text(track.artist).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let date = Formatters.parseISO(track.timestamp) {
                            Text(date, style: .relative).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private var placeholder: some View {
        ContentUnavailableView("Aguardando dados reais", systemImage: "network", description: Text("Conectando ao MeuLab…"))
    }

    private func metric(_ title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: symbol).font(.subheadline).foregroundStyle(.secondary)
            Text(value).font(.title.bold()).monospacedDigit().minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }

    private func detail(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.headline)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}

/// Detached lab-panel windows poll store-backed sections themselves, since the
/// main window's polling in `VisionLabStore` only refreshes its own selection.
private struct SectionSelfPolling: ViewModifier {
    let enabled: Bool
    let section: VisionSection
    @Environment(VisionLabStore.self) private var lab

    func body(content: Content) -> some View {
        if enabled {
            content.polling(every: .seconds(20)) { await lab.refresh(section) }
        } else {
            content
        }
    }
}
