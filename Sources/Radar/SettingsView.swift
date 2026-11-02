import SwiftUI

struct SettingsView: View {
    @Environment(FlightStore.self) private var store
    @AppStorage(AlertChimePlayer.enabledKey) private var alertChimeEnabled = true

    var body: some View {
        Form {
            Section("Visualização espacial") {
                Picker("Raio horizontal", selection: Binding(
                    get: { store.settings.radiusKilometers },
                    set: { store.settings.radiusKilometers = $0 }
                )) {
                    ForEach(RadarSettings.radiusOptions, id: \.self) { radius in
                        Text("\(Int(radius)) km").tag(radius)
                    }
                }
                Picker("Tamanho da mesa", selection: Binding(
                    get: { store.settings.tableScale },
                    set: { store.settings.tableScale = $0 }
                )) {
                    ForEach(RadarSettings.tableScaleOptions, id: \.self) { scale in
                        Text(scale == 1 ? "1× (\(RadarSettings.metersLabel(RadarSettings.baseTableWidthMeters)))" : RadarSettings.scaleLabel(scale)).tag(scale)
                    }
                }
                Text("Mesa maior mostra mais alcance: \(RadarSettings.metersLabel(store.settings.tableWidthMeters)) de largura cobrindo \(Int(store.settings.displayRadiusKilometers)) km de raio (mesma densidade km/m).")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Exagero vertical", selection: Binding(
                    get: { store.settings.verticalExaggeration },
                    set: { store.settings.verticalExaggeration = $0 }
                )) {
                    Text("1×").tag(1.0)
                    Text("1,5×").tag(1.5)
                    Text("2×").tag(2.0)
                }
                Picker("Altitude mínima", selection: Binding(
                    get: { store.settings.minimumAltitudeFeet },
                    set: { store.settings.minimumAltitudeFeet = $0 }
                )) {
                    Text("Solo").tag(0.0)
                    Text("10.000 ft").tag(10_000.0)
                    Text("20.000 ft").tag(20_000.0)
                    Text("30.000 ft").tag(30_000.0)
                }
                Text("A altura dos marcadores é exagerada para legibilidade; não está na mesma escala que a distância horizontal.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Mesa: \(RadarSettings.metersLabel(store.settings.tableWidthMeters)) de largura. Círculo externo = \(Int(store.settings.displayRadiusKilometers)) km. Relevo WGS84 real com exagero vertical de 8× para leitura espacial.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Imersivo e áudio") {
                Toggle("Som espacial", isOn: Binding(
                    get: { store.settings.spatialAudioEnabled },
                    set: { store.settings.spatialAudioEnabled = $0 }
                ))
                Text("Ping posicional curto quando surge um avião novo ou ao selecionar um (no máximo 1 a cada 2 s).")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Som de alerta", isOn: $alertChimeEnabled)
                Text("Toque curto ancorado na janela principal quando chega um alerta novo do homelab.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("No modo imersivo o radar procura uma mesa real; sem mesa, flutua à frente. O visionOS não expõe bússola aos apps: o marcador vermelho é o norte do mapa — gire o radar para alinhá-lo ao norte real.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Dados") {
                Toggle("Nuvens por satélite na mesa", isOn: Binding(
                    get: { store.showClouds },
                    set: { store.showClouds = $0 }
                ))
                Text("GOES-East infravermelho: temperatura dos topos de nuvens, atualizada automaticamente a cada 10 min. A captura pode chegar com atraso.")
                    .font(.caption).foregroundStyle(.secondary)
                Link("Satélite: NASA GIBS / GOES-East ABI",
                     destination: URL(string: "https://worldview.earthdata.nasa.gov/")!)
                    .font(.caption)
                LabeledContent("Endpoint", value: "radar.meulab.fun")
                LabeledContent("Frescor da posição", value: "30 segundos")
                LabeledContent("Atualização", value: "3 s; backoff em falhas")
                Text("Origem: receptor de Franca · 20,51° S · 47,40° O.")
                    .font(.caption).foregroundStyle(.secondary)
                Link("Topografia: Mapzen Terrain Tiles / SRTM, via AWS Open Data",
                     destination: URL(string: "https://registry.opendata.aws/terrain-tiles/")!)
                    .font(.caption)
            }
        }
        .navigationTitle("Configurações")
        .radarSettingsPersistence()
    }
}
