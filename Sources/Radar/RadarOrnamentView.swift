import RealityKit
import SwiftUI

/// Compact radar controls shown as a scene ornament under the volume.
struct RadarOrnamentView: View {
    @Environment(FlightStore.self) private var store

    var body: some View {
        HStack(spacing: 14) {
            Picker("Raio", selection: Binding(
                get: { store.settings.radiusKilometers },
                set: { store.settings.radiusKilometers = $0 }
            )) {
                ForEach(RadarSettings.radiusOptions, id: \.self) { radius in
                    Text("\(Int(radius)) km").tag(radius)
                }
            }
            .pickerStyle(.menu)

            Picker("Mesa", selection: Binding(
                get: { store.settings.tableScale },
                set: { store.settings.tableScale = $0 }
            )) {
                ForEach(RadarSettings.tableScaleOptions, id: \.self) { scale in
                    Text("Mesa \(RadarSettings.scaleLabel(scale))").tag(scale)
                }
            }
            .pickerStyle(.menu)

            Picker("Filtro", selection: Binding(
                get: { store.settings.filter },
                set: { store.settings.filter = $0 }
            )) {
                ForEach(AircraftFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.menu)

            Toggle(isOn: Binding(
                get: { store.showClouds },
                set: { store.showClouds = $0 }
            )) {
                Label("Nuvens", systemImage: "cloud")
            }
            .toggleStyle(.button)

            Button {
                store.setPaused(!store.isPaused)
            } label: {
                Label(store.isPaused ? "Retomar" : "Pausar",
                      systemImage: store.isPaused ? "play.fill" : "pause.fill")
            }

            ImmersiveRadarToggleButton()

            Text("\(Int(store.settings.displayRadiusKilometers)) km")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.cyan)
        }
        // The smaller table proposes less width than the controls need; don't wrap them.
        .fixedSize()
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .glassBackgroundEffect()
    }
}

/// Where the ornament sits for each volume viewpoint, so it always faces the user.
enum RadarViewpointLayout {
    static func ornamentAnchor(for azimuth: SquareAzimuth) -> UnitPoint3D {
        switch azimuth {
        case .front: .bottomFront
        case .back: .bottomBack
        case .left: .bottomLeading
        case .right: .bottomTrailing
        }
    }
}

/// Floating panel for the selected aircraft (ViewAttachmentComponent content).
struct RadarFlightLabel: View {
    let store: FlightStore
    /// Opens the full flight card; nil where the scene has no card.
    var showDetails: (() -> Void)?

    var body: some View {
        if let flight = store.selectedAircraft {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Text(flight.callsign)
                        .font(.headline)
                        .foregroundStyle(.cyan)
                    Spacer(minLength: 0)
                    if let showDetails {
                        Button("Detalhes", systemImage: "info.circle", action: showDetails)
                            .font(.caption)
                            .controlSize(.small)
                    }
                }
                if let subtitle = RadarFlightFacts.subtitle(flight) {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                    let facts = RadarFlightFacts.facts(for: flight, positionAge: store.ageOfPosition(flight, at: Date()))
                    ForEach(Array(stride(from: 0, to: facts.count, by: 2)), id: \.self) { index in
                        GridRow {
                            ForEach(facts[index..<min(index + 2, facts.count)]) { fact in
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(fact.title)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text(fact.value)
                                        .font(.caption.bold())
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                }
                .monospacedDigit()
            }
            .frame(width: 280, alignment: .leading)
            .padding(12)
            .glassBackgroundEffect(in: RoundedRectangle(cornerRadius: 14))
        }
    }

    /// Keeps the panel a constant physical size and height above the aircraft,
    /// regardless of marker, table-size and manipulation scale.
    @MainActor static func place(_ label: Entity, on marker: Entity) {
        let markerScale = max(0.001, marker.scale(relativeTo: nil).y)
        label.position = [0, 0.16 / markerScale, 0]
        // Enlarged: the volume keeps real metres, so its text doesn't grow with distance as in a window.
        label.setScale(SIMD3(repeating: 1.3), relativeTo: nil)
    }
}

/// Restores persisted radius / table size once and saves on every change.
private struct RadarSettingsPersistenceModifier: ViewModifier {
    @Environment(FlightStore.self) private var store

    func body(content: Content) -> some View {
        content
            .onAppear { RadarSettingsPersistence.restoreOnce(into: store) }
            .onChange(of: store.settings) { _, settings in
                RadarSettingsPersistence.save(settings)
            }
    }
}

extension View {
    func radarSettingsPersistence() -> some View {
        modifier(RadarSettingsPersistenceModifier())
    }
}
