import SwiftUI

struct AircraftListView: View {
    @Environment(FlightStore.self) private var store
    let now: Date

    var body: some View {
        if store.filteredAircraft.isEmpty {
            ContentUnavailableView(
                "Nenhuma aeronave recebida",
                systemImage: "airplane.circle",
                description: Text(store.errorMessage == nil ? "Aguardando dados do radar ADS-B." : "Confira a conexão e tente atualizar.")
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(store.filteredAircraft) { flight in
                        Button {
                            store.selectedHex = flight.hex
                        } label: {
                            HStack(spacing: 16) {
                                Image(systemName: "airplane")
                                    .font(.title3.weight(.semibold))
                                    .rotationEffect(.degrees((flight.trackDegrees ?? 0) - 45))
                                    .foregroundStyle(tint(for: flight))
                                    .frame(width: 36)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(flight.callsign)
                                        .font(.headline)
                                    Text([flight.registration, flight.aircraftType].compactMap { $0 }.joined(separator: " · "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                Text(flight.altitudeFeet.map { "\(Int($0).formatted()) ft" } ?? "—")
                                    .frame(width: 115, alignment: .trailing)
                                Text(flight.speedKilometersPerHour.map { "\(Int($0).formatted()) km/h" } ?? "—")
                                    .frame(width: 110, alignment: .trailing)
                                Text(flight.trackDegrees.map { "\(Int($0))°" } ?? "—")
                                    .frame(width: 54, alignment: .trailing)
                                Image(systemName: "chevron.right")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                            }
                            .font(.subheadline)
                            .monospacedDigit()
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .contentShape(RoundedRectangle(cornerRadius: 15))
                            .background(store.selectedHex == flight.hex ? Color.blue.opacity(0.23) : Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 15))
                            .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(store.selectedHex == flight.hex ? Color.blue.opacity(0.75) : Color.white.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func tint(for flight: Aircraft) -> Color {
        if store.selectedHex == flight.hex { return .cyan }
        if !flight.hasPosition || (store.ageOfPosition(flight, at: now) ?? 0) > 15 { return .orange }
        return .blue
    }
}
