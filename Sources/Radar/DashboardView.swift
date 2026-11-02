import SwiftUI

struct DashboardView: View {
    @Environment(FlightStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var showingSettings = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { timeline in
            VStack(alignment: .leading, spacing: 17) {
                header
                StatisticsView(now: timeline.date)
                controls(at: timeline.date)

                if let errorMessage = store.errorMessage {
                    Label(errorMessage, systemImage: "wifi.exclamationmark")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }

                HStack {
                    Text("Tráfego aéreo")
                        .font(.title2.bold())
                    Spacer()
                    Picker("Exibir", selection: Binding(
                        get: { store.settings.filter },
                        set: { store.settings.filter = $0 }
                    )) {
                        ForEach(AircraftFilter.allCases) { value in
                            Text(value.rawValue).tag(value)
                        }
                    }
                    .pickerStyle(.menu)
                }

                AircraftListView(now: timeline.date)
                    .frame(maxHeight: .infinity)

                AircraftDetailView()

                Label("Visualização experimental · não utilizar para navegação ou controle de tráfego aéreo.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(28)
            .frame(minWidth: 840, minHeight: 700)
        }
        .sheet(isPresented: $showingSettings) { SettingsView() }
        .radarSettingsPersistence()
    }

    private var header: some View {
        HStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 17)
                    .fill(.black.opacity(0.42))
                Image("RadarLocalIcon")
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 15))
            }
            .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 3) {
                Text("AeroSpatial")
                    .font(.system(size: 31, weight: .bold))
                Text("Franca, São Paulo")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 9) {
                Circle()
                    .fill(store.isConnected ? .green : .red)
                    .frame(width: 8, height: 8)
                Text(store.isConnected ? "LIVE · ADS-B" : "LIVE · DESCONECTADO")
                    .font(.caption.weight(.bold))
            }
            .foregroundStyle(store.isConnected ? .green : .red)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(store.isConnected ? Color.green.opacity(0.12) : Color.red.opacity(0.12), in: Capsule())

            Button("Configurações", systemImage: "gearshape") { showingSettings = true }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
        }
    }

    private func controls(at timelineDate: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text(store.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                Spacer()

                Button {
                    if store.isSearchOpen {
                        store.isSearchOpen = false
                        dismissWindow(id: "flight-search")
                    } else {
                        store.isSearchOpen = true
                        openWindow(id: "flight-search")
                    }
                } label: {
                    Label(store.isSearchOpen ? "Fechar busca" : "Buscar voos", systemImage: "magnifyingglass")
                }
                .buttonStyle(.bordered)

                Button {
                    if store.isMapOpen {
                        store.isMapOpen = false
                        dismissWindow(id: "radar-map")
                    } else {
                        store.isMapOpen = true
                        openWindow(id: "radar-map")
                    }
                } label: {
                    Label(store.isMapOpen ? "Fechar mapa" : "Mapa interativo", systemImage: "map")
                }
                .buttonStyle(.bordered)

                Button {
                    if store.isVolumeOpen {
                        dismissWindow(id: "radar-volume")
                    } else {
                        openWindow(id: "radar-volume")
                    }
                } label: {
                    Label(store.isVolumeOpen ? "Fechar radar" : "Radar 3D", systemImage: "cube.transparent")
                        .frame(minWidth: 140)
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 12) {
                Text("Mesa \(RadarSettings.metersLabel(store.settings.tableWidthMeters)) · raio \(Int(store.settings.displayRadiusKilometers)) km")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.cyan)
                if let lastReceivedAt = store.lastReceivedAt {
                    Text("\(store.isPaused ? "Última leitura" : "Auto") · \(lastReceivedAt.formatted(date: .omitted, time: .standard))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else if store.isLoading {
                    ProgressView().controlSize(.small)
                }

                if store.isVolumeOpen, store.showClouds {
                    if let captured = store.cloudCapturedAt {
                        Text("GOES-East IR · \(captured.formatted(date: .omitted, time: .shortened)) · \(Int(max(0, timelineDate.timeIntervalSince(captured)) / 60)) min")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.cyan)
                    } else if let error = store.cloudError {
                        Text("Satélite: \(error)")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                    } else {
                        Text("Carregando satélite…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button(store.isPaused ? "Retomar" : "Pausar", systemImage: store.isPaused ? "play.fill" : "pause.fill") {
                    store.setPaused(!store.isPaused)
                }
            }
        }
    }
}
