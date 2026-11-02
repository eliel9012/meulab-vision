import MapKit
import SwiftUI

/// Interactive 2D companion to the 3D radar. Both views share live observations and selection.
struct RadarMapWindowView: View {
    @Environment(FlightStore.self) private var store
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.scenePhase) private var scenePhase
    @State private var position: MapCameraPosition = .region(Self.region(radiusKilometers: 100))

    private static let receiver = CLLocationCoordinate2D(
        latitude: Geodesy.approximateFranca.latitudeDegrees,
        longitude: Geodesy.approximateFranca.longitudeDegrees
    )

    private struct Airport: Identifiable {
        let id: String
        let name: String
        let latitude: Double
        let longitude: Double
        var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
    }

    // Same airport coordinates used by the iPhone radar.
    private static let airports: [Airport] = [
        .init(id: "SIMK", name: "Franca", latitude: -20.5922, longitude: -47.3829),
        .init(id: "SBRP", name: "Ribeirão Preto", latitude: -21.1364, longitude: -47.7767),
        .init(id: "SBSR", name: "São José do Rio Preto", latitude: -20.8166, longitude: -49.4065),
        .init(id: "SBUL", name: "Uberlândia", latitude: -18.8836, longitude: -48.2253),
        .init(id: "SBKP", name: "Viracopos", latitude: -23.0074, longitude: -47.1344),
        .init(id: "SBGR", name: "Guarulhos", latitude: -23.4356, longitude: -46.4731),
        .init(id: "SBSP", name: "Congonhas", latitude: -23.6261, longitude: -46.6564)
    ]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { timeline in
            VStack(spacing: 14) {
                header
                controls
                Map(position: $position, selection: Binding(
                    get: { store.selectedHex },
                    set: { store.selectedHex = $0 }
                )) {
                    MapCircle(center: Self.receiver, radius: store.settings.displayRadiusKilometers * 1_000)
                        .foregroundStyle(.clear)
                        .stroke(.cyan.opacity(0.45), lineWidth: 2)
                    Annotation("Receptor · Franca", coordinate: Self.receiver) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.title3.bold())
                            .foregroundStyle(.white)
                            .padding(9)
                            .background(.blue, in: Circle())
                    }
                    if store.showAirports {
                        ForEach(Self.airports) { airport in
                            Marker("\(airport.name) · \(airport.id)", systemImage: "airplane.departure", coordinate: airport.coordinate)
                                .tint(.orange)
                        }
                    }
                    if store.showTrails {
                        ForEach(store.tracks.keys.sorted(), id: \.self) { hex in
                            if let track = store.tracks[hex], track.count >= 2 {
                                MapPolyline(coordinates: track.map {
                                    CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                                })
                                .stroke(store.selectedHex == hex ? .cyan : .blue.opacity(0.65), lineWidth: store.selectedHex == hex ? 4 : 2)
                            }
                        }
                    }
                    ForEach(store.renderableAircraft(at: timeline.date)) { aircraft in
                        if let latitude = aircraft.latitude, let longitude = aircraft.longitude {
                            Annotation(store.showMapLabels ? aircraft.callsign : "", coordinate: .init(latitude: latitude, longitude: longitude)) {
                                Image(systemName: "airplane")
                                    .font(.title3.bold())
                                    .rotationEffect(.degrees((aircraft.trackDegrees ?? 0) - 45))
                                    .foregroundStyle(store.selectedHex == aircraft.hex ? .cyan : .white)
                                    .padding(8)
                                    .background(store.selectedHex == aircraft.hex ? Color.blue : Color.black.opacity(0.72), in: Circle())
                            }
                            .tag(aircraft.hex)
                        }
                    }
                }
                .mapStyle(style)
                .mapControls {
                    MapCompass()
                    MapScaleView()
                }
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .overlay(alignment: .bottomLeading) {
                    if let selected = store.selectedAircraft {
                        HStack(spacing: 12) {
                            Image(systemName: "airplane").foregroundStyle(.cyan)
                            Text(selected.callsign).bold()
                            Text(selected.altitudeFeet.map { "\(Int($0).formatted()) ft" } ?? "—")
                            Text(selected.speedKilometersPerHour.map { "\(Int($0).formatted()) km/h" } ?? "—")
                        }
                        .font(.callout)
                        .padding(12)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .padding(14)
                    }
                }
                HStack {
                    Text("ADS-B ao vivo · trilhas gravadas nesta sessão")
                    Spacer()
                    Text("\(store.renderableAircraft(at: timeline.date).count) aeronaves no raio")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(20)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28))
            .onChange(of: store.selectedHex) { _, _ in
                if store.followsSelection { focusSelected() }
            }
            .onChange(of: store.selectedAircraft) { _, _ in
                if store.followsSelection { focusSelected() }
            }
            .onChange(of: store.settings.displayRadiusKilometers) { _, radius in
                if !store.followsSelection { position = .region(Self.region(radiusKilometers: radius)) }
            }
        }
        .onAppear { store.isMapOpen = true; store.acquirePolling("radar-map") }
        .onDisappear { store.isMapOpen = false; store.releasePolling("radar-map") }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.acquirePolling("radar-map") }
            else if phase == .background { store.releasePolling("radar-map") }
        }
    }

    private var header: some View {
        HStack {
            Label("Mapa interativo", systemImage: "map.fill").font(.title2.bold())
            Spacer()
            Text("Franca · SP").foregroundStyle(.secondary)
            Button("Fechar janela do mapa", systemImage: "xmark") {
                store.isMapOpen = false
                dismissWindow(id: "radar-map")
            }
            .labelStyle(.iconOnly)
        }
    }

    private var controls: some View {
        HStack(spacing: 9) {
            Picker("Estilo", selection: Binding(get: { store.mapStyle }, set: { store.mapStyle = $0 })) {
                ForEach(RadarMapStyle.allCases) { style in Text(style.rawValue).tag(style) }
            }
            .pickerStyle(.menu)
            Toggle("Aeroportos", isOn: Binding(get: { store.showAirports }, set: { store.showAirports = $0 }))
            Toggle("Trilhas", isOn: Binding(get: { store.showTrails }, set: { store.showTrails = $0 }))
            Toggle("Rótulos", isOn: Binding(get: { store.showMapLabels }, set: { store.showMapLabels = $0 }))
            Toggle("Seguir", isOn: Binding(get: { store.followsSelection }, set: {
                store.followsSelection = $0
                if $0 { focusSelected() }
            }))
            Button("Franca", systemImage: "scope") {
                store.followsSelection = false
                position = .region(Self.region(radiusKilometers: store.settings.displayRadiusKilometers))
            }
        }
        .toggleStyle(.button)
        .buttonStyle(.bordered)
        .font(.subheadline)
    }

    private var style: MapStyle {
        switch store.mapStyle {
        case .standard: .standard
        case .imagery: .imagery
        case .hybrid: .hybrid
        }
    }

    private func focusSelected() {
        guard let aircraft = store.selectedAircraft,
              let latitude = aircraft.latitude, let longitude = aircraft.longitude else { return }
        let span = max(0.25, store.settings.displayRadiusKilometers / 111.32)
        position = .region(MKCoordinateRegion(
            center: .init(latitude: latitude, longitude: longitude),
            span: .init(latitudeDelta: span, longitudeDelta: span)
        ))
    }

    private static func region(radiusKilometers: Double) -> MKCoordinateRegion {
        let latitudeDelta = radiusKilometers * 2 / 111.32
        return MKCoordinateRegion(
            center: receiver,
            span: .init(latitudeDelta: latitudeDelta,
                        longitudeDelta: latitudeDelta / cos(receiver.latitude * .pi / 180))
        )
    }
}
