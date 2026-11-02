import SwiftUI

/// FlightAware results come from MeuLab's live AeroAPI proxy; local hits come from the ADS-B receiver.
struct VisionFlightSearchView: View {
    @Environment(FlightStore.self) private var store
    @Environment(VisionLabStore.self) private var lab
    @Environment(\.openWindow) private var openWindow

    private enum Mode: String, CaseIterable {
        case flights = "Voos"
        case airports = "Aeroportos"
        case route = "Rota"
    }

    private enum BoardKind: String, CaseIterable {
        case departures = "Partidas"
        case arrivals = "Chegadas"
        var apiValue: String { self == .departures ? "scheduled_departures" : "scheduled_arrivals" }
    }

    @State private var mode: Mode = .flights
    @State private var query = ""
    @State private var queriedIdent = ""
    @State private var flightAwareResults: [FlightAwareFlight] = []
    @State private var searchLoading = false
    @State private var searchError: String?
    @State private var airport = "GRU"
    @State private var boardKind: BoardKind = .departures
    @State private var board: [FlightAwareFlight] = []
    @State private var boardLoading = false
    @State private var boardError: String?
    @State private var boardUpdatedAt: Date?
    @State private var routeOrigin = ""
    @State private var routeDestination = ""
    @State private var routeFlights: [FlightAwareFlight] = []
    @State private var routeLoading = false
    @State private var routeError: String?
    @State private var selectedFlight: FlightAwareFlight?

    private let airports = ["GRU", "CGH", "VCP", "RAO"]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("Buscar voos", systemImage: "magnifyingglass").font(.largeTitle.bold())
                Spacer()
                Text("ADS-B · FlightAware").font(.callout).foregroundStyle(.secondary)
            }
            Picker("Área", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            Group {
                switch mode {
                case .flights: flightSearch
                case .airports: airportBoard
                case .route: routeSearch
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Text("Posições no radar: receptor de Franca. Voos e painéis: FlightAware via MeuLab. Sem resultados de demonstração.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(28)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28))
        .sheet(item: $selectedFlight) { FlightAwareDetailSheet(flight: $0) }
        .onAppear { store.isSearchOpen = true; store.acquirePolling("flight-search") }
        .onDisappear { store.isSearchOpen = false; store.releasePolling("flight-search") }
        .task(id: "\(mode.rawValue)-\(airport)-\(boardKind.apiValue)") {
            guard mode == .airports else { return }
            while !Task.isCancelled {
                await loadBoard()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    private var flightSearch: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                TextField("Número, matrícula ou ICAO", text: $query)
                    .textInputAutocapitalization(.characters)
                    .onSubmit { Task { await searchFlightAware() } }
                Button("Buscar no FlightAware", systemImage: "magnifyingglass") {
                    Task { await searchFlightAware() }
                }
                .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 || searchLoading)
            }
            .textFieldStyle(.roundedBorder)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !normalizedQuery.isEmpty {
                        sectionTitle("Radar de Franca · \(localMatches.count) agora")
                        if localMatches.isEmpty {
                            Text("Nenhuma aeronave com esse identificador dentro da cobertura ADS-B.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(localMatches.prefix(30)) { aircraft in
                            Button { showOnRadar(aircraft) } label: {
                                HStack {
                                    Image(systemName: "airplane").foregroundStyle(.cyan)
                                    VStack(alignment: .leading) {
                                        Text(aircraft.callsign).bold()
                                        Text([aircraft.registration, aircraft.aircraftType, aircraft.hex.uppercased()]
                                            .compactMap { $0 }.joined(separator: " · "))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(aircraft.altitudeFeet.map { "\(Int($0).formatted()) ft" } ?? "—")
                                    Image(systemName: "arrow.up.right")
                                }
                                .padding(12)
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        Text("Digite um voo, matrícula ou código ICAO para filtrar as aeronaves recebidas em tempo real.")
                            .foregroundStyle(.secondary)
                    }

                    if searchLoading { ProgressView("Consultando FlightAware…") }
                    if let searchError { errorLabel(searchError) }
                    if !queriedIdent.isEmpty, !searchLoading, searchError == nil {
                        sectionTitle("FlightAware · \(queriedIdent)")
                        if flightAwareResults.isEmpty {
                            Text("Nenhum voo encontrado no FlightAware.").foregroundStyle(.secondary)
                        } else {
                            ForEach(flightAwareResults) { flight in flightRow(flight) }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var airportBoard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Picker("Aeroporto", selection: $airport) {
                    ForEach(airports, id: \.self) { Text($0).tag($0) }
                }
                .frame(width: 180)
                Picker("Painel", selection: $boardKind) {
                    ForEach(BoardKind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                Spacer()
                if boardLoading { ProgressView() }
                Button("Atualizar", systemImage: "arrow.clockwise") { Task { await loadBoard() } }
            }
            HStack {
                Text("\(airport) · \(boardKind.rawValue.lowercased()) · companhias aéreas")
                Spacer()
                if let boardUpdatedAt {
                    Text("Atualizado \(boardUpdatedAt.formatted(date: .omitted, time: .shortened))")
                }
            }
            .font(.caption).foregroundStyle(.secondary)
            if let boardError { errorLabel(boardError) }
            ScrollView {
                LazyVStack(spacing: 9) {
                    ForEach(board) { flight in flightRow(flight) }
                    if board.isEmpty, !boardLoading, boardError == nil {
                        ContentUnavailableView("Sem voos no painel", systemImage: "airplane")
                    }
                }
            }
        }
    }

    private var routeSearch: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                TextField("Origem (GRU)", text: $routeOrigin)
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                TextField("Destino (CGH)", text: $routeDestination)
                Button("Buscar rota", systemImage: "arrow.triangle.branch") { Task { await searchRoute() } }
                    .disabled(routeLoading || (routeOrigin.isEmpty && routeDestination.isEmpty))
            }
            .textFieldStyle(.roundedBorder)
            .textInputAutocapitalization(.characters)
            Text("Consulte partidas da origem ou chegadas do destino no painel FlightAware. Códigos IATA/ICAO; primeira página disponível.")
                .font(.caption).foregroundStyle(.secondary)
            if routeLoading { ProgressView("Buscando rota…") }
            if let routeError { errorLabel(routeError) }
            ScrollView {
                LazyVStack(spacing: 9) {
                    ForEach(routeFlights) { flight in flightRow(flight) }
                    if routeFlights.isEmpty, !routeLoading, routeError == nil {
                        Text(routeOrigin.isEmpty && routeDestination.isEmpty
                             ? "Informe uma origem ou destino para consultar voos reais."
                             : "Nenhum voo encontrado nesta página do painel FlightAware.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var normalizedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }

    private var localMatches: [Aircraft] {
        guard !normalizedQuery.isEmpty else { return [] }
        return store.aircraft.filter { flight in
            [flight.callsign, flight.registration ?? "", flight.hex, flight.aircraftType ?? ""]
                .contains { $0.uppercased().contains(normalizedQuery) }
        }
    }

    private func flightRow(_ flight: FlightAwareFlight) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(flight.bestIdent).font(.headline)
                Text("\(flight.origin?.bestCode ?? "—") → \(flight.destination?.bestCode ?? "—")")
                    .font(.subheadline)
                Spacer()
                Text(status(flight)).foregroundStyle(.secondary)
                Button("Detalhes", systemImage: "info.circle") { selectedFlight = flight }
                    .labelStyle(.iconOnly)
            }
            HStack(spacing: 16) {
                if let out = FlightAwareTime.short(flight.actualOut ?? flight.estimatedOut ?? flight.scheduledOut) {
                    Text("Saída \(out)")
                }
                if let arrival = FlightAwareTime.short(flight.actualIn ?? flight.estimatedIn ?? flight.scheduledIn) {
                    Text("Chegada \(arrival)")
                }
                if let terminal = flight.terminalOrigin, let gate = flight.gateOrigin {
                    Text("T\(terminal) · Portão \(gate)")
                }
                Spacer()
                if let aircraft = localAircraft(for: flight) {
                    Button("Ver no radar", systemImage: "location") { showOnRadar(aircraft) }
                } else {
                    Text("Fora da cobertura local").foregroundStyle(.tertiary)
                }
            }
            .font(.caption)
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func localAircraft(for flight: FlightAwareFlight) -> Aircraft? {
        let ids = [flight.ident, flight.identIcao, flight.identIata]
            .compactMap { $0?.uppercased() }
        return store.aircraft.first { ids.contains($0.callsign.uppercased()) }
    }

    private func showOnRadar(_ aircraft: Aircraft) {
        store.selectedHex = aircraft.hex
        store.followsSelection = true
        lab.select(.radar)
        openWindow(id: "radar-map")
    }

    private func searchFlightAware() async {
        let ident = normalizedQuery
        guard ident.count >= 2 else { return }
        searchLoading = true
        searchError = nil
        queriedIdent = ident
        flightAwareResults = []
        defer { searchLoading = false }
        do {
            let response: FlightAwareFlightResponse = try await VisionAPIClient.shared.fetch("api/flightaware/flight", query: [
                URLQueryItem(name: "ident", value: ident),
                URLQueryItem(name: "max_pages", value: "1")
            ])
            flightAwareResults = response.data.flights ?? []
        } catch {
            searchError = error.localizedDescription
        }
    }

    private func loadBoard() async {
        boardLoading = true
        boardError = nil
        board = []
        defer { boardLoading = false }
        do {
            let response: FlightAwareAirportBoardResponse = try await VisionAPIClient.shared.fetch("api/flightaware/airport/board", query: [
                URLQueryItem(name: "airport", value: airport),
                URLQueryItem(name: "kind", value: boardKind.apiValue),
                URLQueryItem(name: "type", value: "Airline"),
                URLQueryItem(name: "max_pages", value: "1")
            ])
            guard !Task.isCancelled else { return }
            board = boardKind == .departures ? response.data.scheduledDepartures ?? [] : response.data.scheduledArrivals ?? []
            boardUpdatedAt = Date()
        } catch {
            guard !Task.isCancelled else { return }
            boardError = error.localizedDescription
        }
    }

    private func searchRoute() async {
        let origin = routeOrigin.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let destination = routeDestination.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard [origin, destination].allSatisfy({ $0.isEmpty || (3...4).contains($0.count) && $0.allSatisfy(\.isLetter) }) else {
            routeError = "Use códigos IATA ou ICAO com 3 ou 4 letras."
            return
        }
        guard !origin.isEmpty || !destination.isEmpty else { return }
        routeLoading = true
        routeError = nil
        routeFlights = []
        defer { routeLoading = false }
        let airport = origin.isEmpty ? destination : origin
        let kind = origin.isEmpty ? "scheduled_arrivals" : "scheduled_departures"
        do {
            let response: FlightAwareAirportBoardResponse = try await VisionAPIClient.shared.fetch("api/flightaware/airport/board", query: [
                URLQueryItem(name: "airport", value: airport),
                URLQueryItem(name: "kind", value: kind),
                URLQueryItem(name: "type", value: "Airline"),
                URLQueryItem(name: "max_pages", value: "1")
            ])
            let flights = origin.isEmpty ? response.data.scheduledArrivals ?? [] : response.data.scheduledDepartures ?? []
            routeFlights = flights.filter { flight in
                (origin.isEmpty || airportMatches(flight.origin, code: origin)) &&
                (destination.isEmpty || airportMatches(flight.destination, code: destination))
            }
        } catch {
            routeError = error.localizedDescription
        }
    }

    private func airportMatches(_ airport: FlightAwareAirportRef?, code: String) -> Bool {
        guard let airport else { return false }
        return [airport.code, airport.codeIata, airport.codeIcao]
            .compactMap { $0?.uppercased() }.contains(code)
    }

    private func status(_ flight: FlightAwareFlight) -> String {
        if flight.actualIn != nil || flight.actualOn != nil { return "Pousado" }
        if flight.actualOff != nil || flight.actualOut != nil { return "Em voo" }
        if flight.estimatedOut != nil || flight.scheduledOut != nil { return "Programado" }
        return "Sem status"
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.headline).padding(.top, 4)
    }

    private func errorLabel(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.callout).foregroundStyle(.orange)
    }
}

private struct FlightAwareDetailSheet: View {
    let flight: FlightAwareFlight
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(flight.bestIdent).font(.largeTitle.bold())
                Spacer()
                Button("Fechar", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly)
            }
            Text("\(flight.origin?.name ?? flight.origin?.bestCode ?? "—") → \(flight.destination?.name ?? flight.destination?.bestCode ?? "—")")
                .font(.title3)
            detail("Operadora", flight.operator ?? flight.operatorIata ?? flight.operatorIcao)
            detail("Saída prevista", FlightAwareTime.short(flight.scheduledOut))
            detail("Saída estimada", FlightAwareTime.short(flight.estimatedOut))
            detail("Saída real", FlightAwareTime.short(flight.actualOut))
            detail("Chegada prevista", FlightAwareTime.short(flight.scheduledIn))
            detail("Chegada estimada", FlightAwareTime.short(flight.estimatedIn))
            detail("Chegada real", FlightAwareTime.short(flight.actualIn))
            detail("Terminal / portão origem", [flight.terminalOrigin, flight.gateOrigin].compactMap { $0 }.joined(separator: " / "))
            detail("Terminal / portão destino", [flight.terminalDestination, flight.gateDestination].compactMap { $0 }.joined(separator: " / "))
            Spacer()
            Text("Fonte: FlightAware via MeuLab").font(.caption).foregroundStyle(.secondary)
        }
        .padding(28)
        .frame(width: 520, height: 570)
    }

    private func detail(_ title: String, _ value: String?) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value.flatMap { $0.isEmpty ? nil : $0 } ?? "—")
        }
        .font(.callout)
    }
}
