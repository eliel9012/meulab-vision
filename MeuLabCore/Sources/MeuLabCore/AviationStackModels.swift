import Foundation

public struct AviationStackFlightResponse: Codable, Sendable {
    public let pagination: AviationStackPagination?
    public let data: [AviationStackFlightData]

    public init(pagination: AviationStackPagination?, data: [AviationStackFlightData]) {
        self.pagination = pagination
        self.data = data
    }
}

public struct AviationStackPagination: Codable, Sendable {
    public let limit: Int
    public let offset: Int
    public let count: Int
    public let total: Int

    public init(limit: Int, offset: Int, count: Int, total: Int) {
        self.limit = limit
        self.offset = offset
        self.count = count
        self.total = total
    }
}

public struct AviationStackFlightData: Codable, Sendable {
    public let flightDate: String?
    public let flightStatus: String?
    public let departure: AviationStackAirport?
    public let arrival: AviationStackAirport?
    public let airline: AviationStackAirline?
    public let flight: AviationStackFlight?
    
    enum CodingKeys: String, CodingKey {
        case flightDate = "flight_date"
        case flightStatus = "flight_status"
        case departure, arrival, airline, flight
    }

    public init(flightDate: String?, flightStatus: String?, departure: AviationStackAirport?, arrival: AviationStackAirport?, airline: AviationStackAirline?, flight: AviationStackFlight?) {
        self.flightDate = flightDate
        self.flightStatus = flightStatus
        self.departure = departure
        self.arrival = arrival
        self.airline = airline
        self.flight = flight
    }
}

public struct AviationStackAirport: Codable, Sendable {
    public let airport: String?
    public let timezone: String?
    public let iata: String?
    public let icao: String?
    public let terminal: String?
    public let gate: String?
    public let scheduled: String?
    public let estimated: String?
    public let actual: String?
    public let estimatedRunway: String?
    public let actualRunway: String?
    
    enum CodingKeys: String, CodingKey {
        case airport, timezone, iata, icao, terminal, gate, scheduled, estimated, actual
        case estimatedRunway = "estimated_runway"
        case actualRunway = "actual_runway"
    }

    public init(airport: String?, timezone: String?, iata: String?, icao: String?, terminal: String?, gate: String?, scheduled: String?, estimated: String?, actual: String?, estimatedRunway: String?, actualRunway: String?) {
        self.airport = airport
        self.timezone = timezone
        self.iata = iata
        self.icao = icao
        self.terminal = terminal
        self.gate = gate
        self.scheduled = scheduled
        self.estimated = estimated
        self.actual = actual
        self.estimatedRunway = estimatedRunway
        self.actualRunway = actualRunway
    }
}

public struct AviationStackAirline: Codable, Sendable {
    public let name: String?
    public let iata: String?
    public let icao: String?

    public init(name: String?, iata: String?, icao: String?) {
        self.name = name
        self.iata = iata
        self.icao = icao
    }
}

public struct AviationStackFlight: Codable, Sendable {
    public let number: String?
    public let iata: String?
    public let icao: String?
    public let codeshared: AviationStackCodeshared?

    public init(number: String?, iata: String?, icao: String?, codeshared: AviationStackCodeshared?) {
        self.number = number
        self.iata = iata
        self.icao = icao
        self.codeshared = codeshared
    }
}

public struct AviationStackCodeshared: Codable, Sendable {
    public let airlineName: String?
    public let airlineIata: String?
    public let airlineIcao: String?
    public let flightNumber: String?
    public let flightIata: String?
    public let flightIcao: String?
    
    enum CodingKeys: String, CodingKey {
        case airlineName = "airline_name"
        case airlineIata = "airline_iata"
        case airlineIcao = "airline_icao"
        case flightNumber = "flight_number"
        case flightIata = "flight_iata"
        case flightIcao = "flight_icao"
    }

    public init(airlineName: String?, airlineIata: String?, airlineIcao: String?, flightNumber: String?, flightIata: String?, flightIcao: String?) {
        self.airlineName = airlineName
        self.airlineIata = airlineIata
        self.airlineIcao = airlineIcao
        self.flightNumber = flightNumber
        self.flightIata = flightIata
        self.flightIcao = flightIcao
    }
}

// MARK: - FlightAware (AeroAPI via MeuLab backend)

/// Backend wrapper for `/api/flightaware/airport/board`.
public struct FlightAwareAirportBoardResponse: Codable, Equatable, Sendable {
    public let airport: String
    public let kind: String
    public let data: FlightAwareBoardData

    public init(airport: String, kind: String, data: FlightAwareBoardData) {
        self.airport = airport
        self.kind = kind
        self.data = data
    }
}

/// `data` object contains one of these arrays depending on the "kind".
public struct FlightAwareBoardData: Codable, Equatable, Sendable {
    public let scheduledDepartures: [FlightAwareFlight]?
    public let scheduledArrivals: [FlightAwareFlight]?
    public let departures: [FlightAwareFlight]?
    public let arrivals: [FlightAwareFlight]?
    public let enroute: [FlightAwareFlight]?

    enum CodingKeys: String, CodingKey {
        case scheduledDepartures = "scheduled_departures"
        case scheduledArrivals = "scheduled_arrivals"
        case departures
        case arrivals
        case enroute
    }

    public init(scheduledDepartures: [FlightAwareFlight]?, scheduledArrivals: [FlightAwareFlight]?, departures: [FlightAwareFlight]?, arrivals: [FlightAwareFlight]?, enroute: [FlightAwareFlight]?) {
        self.scheduledDepartures = scheduledDepartures
        self.scheduledArrivals = scheduledArrivals
        self.departures = departures
        self.arrivals = arrivals
        self.enroute = enroute
    }
}

/// Backend wrapper for `/api/flightaware/flight`.
public struct FlightAwareFlightResponse: Codable, Equatable, Sendable {
    public let ident: String
    public let data: FlightAwareFlightData

    public init(ident: String, data: FlightAwareFlightData) {
        self.ident = ident
        self.data = data
    }
}

public struct FlightAwareFlightData: Codable, Equatable, Sendable {
    public let flights: [FlightAwareFlight]?

    public init(flights: [FlightAwareFlight]?) {
        self.flights = flights
    }
}

public struct FlightAwareAirportRef: Codable, Equatable, Sendable {
    public let code: String?
    public let codeIcao: String?
    public let codeIata: String?
    public let name: String?
    public let city: String?
    public let country: String?

    enum CodingKeys: String, CodingKey {
        case code
        case codeIcao = "code_icao"
        case codeIata = "code_iata"
        case name, city, country
    }

    public var bestCode: String {
        codeIata ?? code ?? codeIcao ?? "-"
    }

    public init(code: String?, codeIcao: String?, codeIata: String?, name: String?, city: String?, country: String?) {
        self.code = code
        self.codeIcao = codeIcao
        self.codeIata = codeIata
        self.name = name
        self.city = city
        self.country = country
    }
}

public struct FlightAwareFlight: Codable, Identifiable, Equatable, Sendable {
    public let faFlightID: String?

    public let ident: String?
    public let identIcao: String?
    public let identIata: String?

    public let `operator`: String?
    public let operatorIcao: String?
    public let operatorIata: String?

    public let origin: FlightAwareAirportRef?
    public let destination: FlightAwareAirportRef?

    // Times (ISO8601 Z)
    public let scheduledOut: String?
    public let estimatedOut: String?
    public let actualOut: String?
    public let scheduledOff: String?
    public let estimatedOff: String?
    public let actualOff: String?

    public let scheduledOn: String?
    public let estimatedOn: String?
    public let actualOn: String?
    public let scheduledIn: String?
    public let estimatedIn: String?
    public let actualIn: String?

    // Gate/terminal
    public let terminalOrigin: String?
    public let gateOrigin: String?
    public let terminalDestination: String?
    public let gateDestination: String?

    enum CodingKeys: String, CodingKey {
        case faFlightID = "fa_flight_id"
        case ident
        case identIcao = "ident_icao"
        case identIata = "ident_iata"
        case `operator`
        case operatorIcao = "operator_icao"
        case operatorIata = "operator_iata"
        case origin, destination
        case scheduledOut = "scheduled_out"
        case estimatedOut = "estimated_out"
        case actualOut = "actual_out"
        case scheduledOff = "scheduled_off"
        case estimatedOff = "estimated_off"
        case actualOff = "actual_off"
        case scheduledOn = "scheduled_on"
        case estimatedOn = "estimated_on"
        case actualOn = "actual_on"
        case scheduledIn = "scheduled_in"
        case estimatedIn = "estimated_in"
        case actualIn = "actual_in"
        case terminalOrigin = "terminal_origin"
        case gateOrigin = "gate_origin"
        case terminalDestination = "terminal_destination"
        case gateDestination = "gate_destination"
    }

    public var id: String {
        if let faFlightID, !faFlightID.isEmpty { return faFlightID }
        let parts = [
            identIcao, ident, scheduledOut, estimatedOut, scheduledIn, estimatedIn
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.joined(separator: "|")
    }

    public var bestIdent: String {
        identIata ?? identIcao ?? ident ?? "-"
    }

    public init(faFlightID: String?, ident: String?, identIcao: String?, identIata: String?, `operator`: String?, operatorIcao: String?, operatorIata: String?, origin: FlightAwareAirportRef?, destination: FlightAwareAirportRef?, scheduledOut: String?, estimatedOut: String?, actualOut: String?, scheduledOff: String?, estimatedOff: String?, actualOff: String?, scheduledOn: String?, estimatedOn: String?, actualOn: String?, scheduledIn: String?, estimatedIn: String?, actualIn: String?, terminalOrigin: String?, gateOrigin: String?, terminalDestination: String?, gateDestination: String?) {
        self.faFlightID = faFlightID
        self.ident = ident
        self.identIcao = identIcao
        self.identIata = identIata
        self.`operator` = `operator`
        self.operatorIcao = operatorIcao
        self.operatorIata = operatorIata
        self.origin = origin
        self.destination = destination
        self.scheduledOut = scheduledOut
        self.estimatedOut = estimatedOut
        self.actualOut = actualOut
        self.scheduledOff = scheduledOff
        self.estimatedOff = estimatedOff
        self.actualOff = actualOff
        self.scheduledOn = scheduledOn
        self.estimatedOn = estimatedOn
        self.actualOn = actualOn
        self.scheduledIn = scheduledIn
        self.estimatedIn = estimatedIn
        self.actualIn = actualIn
        self.terminalOrigin = terminalOrigin
        self.gateOrigin = gateOrigin
        self.terminalDestination = terminalDestination
        self.gateDestination = gateDestination
    }
}

public enum FlightAwareTime {
    public static func parse(_ iso: String?) -> Date? {
        guard let iso, !iso.isEmpty else { return nil }
        return CoreFormatters.isoDateNoFrac.date(from: iso) ?? CoreFormatters.isoDate.date(from: iso)
    }

    public static func short(_ iso: String?) -> String? {
        guard let d = parse(iso) else { return nil }
        return CoreFormatters.time.string(from: d)
    }
}
