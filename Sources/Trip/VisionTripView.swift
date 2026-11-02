import SwiftUI

struct VisionTripView: View {
    @Environment(FlightStore.self) private var radar
    @Environment(VisionLabStore.self) private var lab
    @Environment(\.openWindow) private var openWindow

    @State private var days: [VisionTripDay] = []
    @State private var itineraryError: String?
    @State private var selectedFlightID: String?
    @State private var expandedDayID: String?
    @State private var liveFlight: FlightAwareFlight?
    @State private var liveError: String?
    @State private var weather: [String: VisionTripWeather] = [:]
    @State private var weatherErrors: [String: String] = [:]
    @State private var checking = false
    @State private var checkedAt: Date?

    private var flights: [VisionTripFlight] { VisionTripFlight.flights(in: days) }
    private var selectedFlight: VisionTripFlight? {
        flights.first { $0.id == selectedFlightID }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if let itineraryError {
                        Label(itineraryError, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    } else if days.isEmpty {
                        ProgressView("Carregando roteiro…")
                    } else {
                        nextStopCard(at: timeline.date)
                        flightSection(at: timeline.date)
                        weatherSection
                        itinerarySection
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollInputBehavior(.enabled, for: .look)
        }
        .padding(28)
        .toolbar {
            ToolbarItemGroup(placement: .bottomOrnament) {
                if checking { ProgressView() }
                Button("Atualizar status e clima", systemImage: "arrow.clockwise") {
                    Task { await refreshSelected(forceWeather: true) }
                }
                .disabled(checking || selectedFlight == nil)
            }
        }
        .task { loadItinerary() }
        .polling(every: .seconds(300), id: selectedFlightID) {
            guard selectedFlightID != nil else { return }
            await refreshSelected()
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Viagem", systemImage: "suitcase.rolling.fill").font(.largeTitle.bold())
                Text("\(VisionTripCalendar.rangeLabel(days) ?? "Roteiro") · roteiro do iPhone")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func nextStopCard(at now: Date) -> some View {
        let upcoming = days.flatMap { day in day.events.map { (day, $0) } }
            .compactMap { day, event -> (VisionTripDay, VisionTripEvent, Date)? in
                guard let date = event.date(day: day), date > now else { return nil }
                return (day, event, date)
            }
            .min { $0.2 < $1.2 }
        return VStack(alignment: .leading, spacing: 9) {
            Label("Próximo compromisso", systemImage: "clock.arrow.circlepath")
                .font(.caption.bold())
            if let upcoming {
                Text("\(upcoming.1.icon) \(upcoming.1.title)").font(.title2.bold())
                HStack {
                    Text("\(upcoming.0.date) · \(upcoming.1.time)")
                    Spacer()
                    Text(upcoming.2, style: .relative)
                }
                .font(.callout)
                Text(upcoming.1.desc).font(.callout).lineLimit(3)
            } else {
                Text("Roteiro concluído").font(.title2.bold())
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.blue.opacity(0.18), in: RoundedRectangle(cornerRadius: 20))
        .depthCard()
    }

    private func flightSection(at now: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Meus Voos", systemImage: "airplane.circle.fill").font(.title2.bold())
                Spacer()
                Text("\(flights.count) trechos confirmados")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let selectedFlight {
                flightHero(selectedFlight, now: now)
            }
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(flights) { flight in
                        Button {
                            selectedFlightID = flight.id
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(flight.displayCode).font(.headline)
                                Text(flight.route).font(.callout)
                                Text("\(flight.day.date) · \(flight.event.time)")
                                    .font(.caption)
                                    .foregroundStyle(selectedFlightID == flight.id ? .primary : .secondary)
                            }
                            .frame(width: 148, alignment: .leading)
                            .padding(13)
                            .background(selectedFlightID == flight.id ? .blue.opacity(0.34) : .white.opacity(0.08),
                                        in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                        .liftCard(cornerRadius: 14)
                        .accessibilityAddTraits(selectedFlightID == flight.id ? .isSelected : [])
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func flightHero(_ flight: VisionTripFlight, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading) {
                    Text(flight.displayCode).font(.title.bold())
                    Text(flight.route).font(.title3)
                    Text("\(flight.day.date) · saída \(flight.event.time) no horário local")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let aircraft = liveAircraft(for: flight) {
                    Button("Ver no radar", systemImage: "location") {
                        radar.selectedHex = aircraft.hex
                        radar.followsSelection = true
                        lab.select(.radar)
                        openWindow(id: "radar-map")
                    }
                }
            }
            HStack(spacing: 16) {
                Label(status(for: flight, now: now), systemImage: liveFlight == nil ? "calendar" : "checkmark.circle")
                    .foregroundStyle(liveFlight == nil ? Color.secondary : Color.green)
                if checking { ProgressView().controlSize(.small) }
                Spacer()
                if let checkedAt { Text("Consulta \(checkedAt.formatted(date: .omitted, time: .shortened))") }
            }
            .font(.callout)
            if let liveFlight {
                HStack(spacing: 16) {
                    Text("FlightAware").font(.caption.bold()).foregroundStyle(.cyan)
                    if let out = FlightAwareTime.parse(liveFlight.actualOut ?? liveFlight.estimatedOut ?? liveFlight.scheduledOut) {
                        Text("Saída \(time(out, zone: VisionTripAirport.known[flight.originCode]?.timeZone))")
                    }
                    if let arrival = FlightAwareTime.parse(liveFlight.actualIn ?? liveFlight.estimatedIn ?? liveFlight.scheduledIn) {
                        let code = liveFlight.destination?.codeIata ?? flight.destinationCode
                        Text("Chegada \(time(arrival, zone: VisionTripAirport.known[code]?.timeZone))")
                    }
                    if let gate = liveFlight.gateOrigin { Text("Portão \(gate)") }
                }
                .font(.caption)
                if let legDestination = liveFlight.destination?.codeIata,
                   legDestination != flight.destinationCode {
                    Text("Trecho consultado: \(flight.originCode) → \(legDestination). O roteiro segue até \(flight.destinationCode) com conexão.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text(liveError ?? "Horários do roteiro. Status FlightAware indisponível para a data deste trecho.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(flight.event.desc).font(.callout).lineLimit(3)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
        .offset(z: SpatialDepth.card)
    }

    private var weatherSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Clima na rota", systemImage: "cloud.sun.fill").font(.title2.bold())
            if let flight = selectedFlight {
                HStack(alignment: .top, spacing: 12) {
                    weatherCard(code: flight.originCode, title: "Origem", target: flight.departure)
                    weatherCard(code: flight.destinationCode, title: "Destino",
                                target: FlightAwareTime.parse(liveFlight?.actualIn ?? liveFlight?.estimatedIn ?? liveFlight?.scheduledIn)
                                    ?? flight.plannedArrival)
                }
            }
            Text("Previsão por hora: Open-Meteo. Horários planejados: roteiro do iPhone; estimativas e status: FlightAware.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func weatherCard(code: String, title: String, target: Date?) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(title).font(.caption.bold()).foregroundStyle(.cyan)
                Spacer()
                Text(code).font(.caption.bold())
            }
            if let data = weather[code] {
                Text(data.airport.name).font(.headline)
                HStack {
                    Image(systemName: data.symbol).foregroundStyle(.yellow).accessibilityHidden(true)
                    Text("\(Int(data.temperature.rounded()))°C").font(.title2.bold())
                    Text(data.description).font(.caption).foregroundStyle(.secondary)
                }
                if let target, let forecast = nearestHour(to: target, in: data.hours) {
                    Text("No horário do trecho: \(Int(forecast.temperature.rounded()))°C · chuva \(forecast.rainChance)%")
                        .font(.caption.bold())
                }
                Text("Próximas horas · °C / chuva")
                    .font(.caption2).foregroundStyle(.secondary)
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(data.hours.filter { $0.time >= Date().addingTimeInterval(-3_600) }.prefix(6)) { hour in
                            VStack(spacing: 3) {
                                Text(time(hour.time, zone: data.airport.timeZone)).font(.caption2)
                                Text("\(Int(hour.temperature.rounded()))°").font(.caption.bold())
                                Text("\(hour.rainChance)%").font(.caption2).foregroundStyle(.secondary)
                            }
                            .frame(width: 40)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            } else if let error = weatherErrors[code] {
                Text(error).font(.caption).foregroundStyle(.orange)
            } else {
                ProgressView("Consultando…").font(.caption)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
        .depthCard()
    }

    private var itinerarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Roteiro", systemImage: "list.bullet.rectangle").font(.title2.bold())
            ForEach(days) { day in
                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        expandedDayID = expandedDayID == day.id ? nil : day.id
                    } label: {
                        HStack {
                            Text(day.displayDate).font(.headline)
                            Spacer()
                            Text(day.title).font(.callout).foregroundStyle(.secondary)
                            Image(systemName: expandedDayID == day.id ? "chevron.up" : "chevron.down")
                        }
                        .padding(15)
                    }
                    .buttonStyle(.plain)
                    .liftCard(cornerRadius: 14, depth: 0)
                    .accessibilityValue(expandedDayID == day.id ? "Expandido" : "Recolhido")
                    if expandedDayID == day.id {
                        ForEach(day.events) { event in
                            HStack(alignment: .top, spacing: 12) {
                                Text(event.time).font(.caption.monospacedDigit()).frame(width: 68, alignment: .leading)
                                Text(event.icon)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(event.title).font(.callout.bold())
                                    Text(event.desc).font(.caption).foregroundStyle(.secondary)
                                    if let address = event.address {
                                        Text(address).font(.caption2).foregroundStyle(.tertiary)
                                    }
                                    if event.pending { Text("Pendente").font(.caption.bold()).foregroundStyle(.orange) }
                                    if let lat = event.lat, let lon = event.lon,
                                       let url = URL(string: "https://maps.apple.com/?ll=\(lat),\(lon)") {
                                        Link("Abrir no Mapas", destination: url).font(.caption)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 15)
                            .padding(.vertical, 9)
                        }
                    }
                }
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private func loadItinerary() {
        guard days.isEmpty else { return }
        do {
            days = try VisionTripItinerary.load()
            let now = Date()
            selectedFlightID = flights.first { $0.departure >= now.addingTimeInterval(-10_800) }?.id ?? flights.last?.id
            expandedDayID = days.first { day in
                day.events.contains { ($0.date(day: day) ?? .distantPast) > now }
            }?.id ?? days.last?.id
        } catch {
            itineraryError = error.localizedDescription
        }
    }

    private func refreshSelected(forceWeather: Bool = false) async {
        guard let flight = selectedFlight else { return }
        checking = true
        liveError = nil
        liveFlight = nil
        defer { checking = false; checkedAt = Date() }

        do {
            let response: FlightAwareFlightResponse = try await VisionAPIClient.shared.fetch("api/flightaware/flight", query: [
                URLQueryItem(name: "ident", value: flight.ident),
                URLQueryItem(name: "max_pages", value: "1")
            ])
            guard !Task.isCancelled, selectedFlightID == flight.id else { return }
            liveFlight = (response.data.flights ?? [])
                .compactMap { candidate -> (FlightAwareFlight, TimeInterval)? in
                    guard let scheduled = FlightAwareTime.parse(candidate.scheduledOut ?? candidate.estimatedOut),
                          matchesRoute(candidate, flight: flight) else { return nil }
                    return (candidate, abs(scheduled.timeIntervalSince(flight.departure)))
                }
                .filter { $0.1 <= 18 * 3_600 }
                .min { $0.1 < $1.1 }?.0
        } catch {
            guard !Task.isCancelled, selectedFlightID == flight.id else { return }
            liveError = "FlightAware: \(error.localizedDescription)"
        }

        for code in Set([flight.originCode, flight.destinationCode]) {
            guard !Task.isCancelled, selectedFlightID == flight.id else { return }
            if !forceWeather, let cached = weather[code], Date().timeIntervalSince(cached.fetchedAt) < 1_800 { continue }
            guard let airport = VisionTripAirport.known[code] else {
                weatherErrors[code] = "Aeroporto sem coordenadas no roteiro."
                continue
            }
            do {
                weather[code] = try await VisionTripWeatherService.fetch(airport)
                weatherErrors[code] = nil
            } catch {
                weatherErrors[code] = error.localizedDescription
            }
        }
    }

    private func matchesRoute(_ candidate: FlightAwareFlight, flight: VisionTripFlight) -> Bool {
        let origin = [candidate.origin?.code, candidate.origin?.codeIata, candidate.origin?.codeIcao]
            .compactMap { $0?.uppercased() }
        let destination = [candidate.destination?.code, candidate.destination?.codeIata, candidate.destination?.codeIcao]
            .compactMap { $0?.uppercased() }
        let isConnection = flight.event.desc.localizedCaseInsensitiveContains("conexão")
        return origin.contains(flight.originCode) &&
            (destination.contains(flight.destinationCode) || isConnection)
    }

    private func liveAircraft(for flight: VisionTripFlight) -> Aircraft? {
        let aliases: [String: String] = ["AD": "AZU", "LA": "LAN", "UX": "AEA", "IB": "IBE", "BA": "BAW"]
        let digits = String(flight.ident.drop(while: { !$0.isNumber }))
        let prefix = String(flight.ident.prefix(while: { !$0.isNumber }))
        let candidates = [flight.ident, (aliases[prefix] ?? prefix) + digits]
        return radar.aircraft.first { candidates.contains($0.callsign.uppercased()) }
    }

    private func status(for flight: VisionTripFlight, now: Date) -> String {
        if let liveFlight {
            if liveFlight.actualIn != nil || liveFlight.actualOn != nil { return "Pousado · FlightAware" }
            if liveFlight.actualOut != nil || liveFlight.actualOff != nil { return "Em voo · FlightAware" }
            if liveFlight.estimatedOut != nil { return "Horário estimado · FlightAware" }
            return "Programado · FlightAware"
        }
        return flight.departure < now ? "Horário do roteiro · voo passado" : "Horário do roteiro · a confirmar"
    }

    private func nearestHour(to date: Date, in hours: [VisionTripWeather.Hour]) -> VisionTripWeather.Hour? {
        guard let best = hours.min(by: { abs($0.time.timeIntervalSince(date)) < abs($1.time.timeIntervalSince(date)) }),
              abs(best.time.timeIntervalSince(date)) <= 3_600 else { return nil }
        return best
    }

    private func time(_ date: Date, zone: TimeZone?) -> String {
        date.formatted(Self.timeStyle(zone ?? .current))
    }

    /// "HH:mm" sem alocar DateFormatter por render.
    private static func timeStyle(_ zone: TimeZone) -> Date.VerbatimFormatStyle {
        Date.VerbatimFormatStyle(
            format: "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)",
            timeZone: zone,
            calendar: Calendar(identifier: .gregorian))
    }
}
