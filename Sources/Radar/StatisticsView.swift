import SwiftUI

struct StatisticsView: View {
    @Environment(FlightStore.self) private var store
    let now: Date

    var body: some View {
        HStack(spacing: 12) {
            metric("Recebidas", value: "\(store.receivedCount)", symbol: "antenna.radiowaves.left.and.right")
            metric("Posições recentes", value: "\(store.renderableAircraft(at: now).count)", symbol: "clock")
            metric("Altitude máx.", value: store.maxAltitudeFeet.map { "\(Int($0).formatted()) ft" } ?? "—", symbol: "mountain.2")
            metric("Velocidade máx.", value: store.maxSpeedKilometersPerHour.map { "\(Int($0).formatted()) km/h" } ?? "—", symbol: "speedometer")
        }
    }

    private func metric(_ label: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.blue)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .minimumScaleFactor(0.8)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.16)))
    }
}
