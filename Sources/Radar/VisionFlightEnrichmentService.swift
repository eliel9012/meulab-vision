import Foundation

struct VisionAircraftPhoto {
    let url: URL
    let photographer: String?
    let source: String
}

/// Outcome of one photo source. `failed` (network, server error) is not the same as
/// `notFound`: only an answer from the source may be cached.
enum VisionPhotoLookup {
    case found(VisionAircraftPhoto)
    case notFound
    case failed

    var photo: VisionAircraftPhoto? {
        if case .found(let photo) = self { return photo }
        return nil
    }

    func merged(with next: VisionPhotoLookup) -> VisionPhotoLookup {
        switch (self, next) {
        case (_, .found): next
        case (.failed, _), (_, .failed): .failed
        default: .notFound
        }
    }
}

/// Entries live 5 minutes; inserting drops expired ones and, past the limit, the oldest.
struct VisionEnrichmentCache<Value> {
    static var lifetime: TimeInterval { 300 }

    private var entries: [String: (value: Value, fetchedAt: Date)] = [:]
    let limit: Int

    init(limit: Int = 200) {
        self.limit = limit
    }

    var count: Int { entries.count }

    func value(for key: String, now: Date = Date()) -> Value? {
        guard let entry = entries[key], now.timeIntervalSince(entry.fetchedAt) < Self.lifetime else { return nil }
        return entry.value
    }

    mutating func insert(_ value: Value, for key: String, now: Date = Date()) {
        entries = entries.filter { now.timeIntervalSince($0.value.fetchedAt) < Self.lifetime }
        entries[key] = (value, now)
        let excess = entries.count - limit
        guard excess > 0 else { return }
        let oldest = entries.sorted { $0.value.fetchedAt < $1.value.fetchedAt }.prefix(excess)
        for entry in oldest { entries[entry.key] = nil }
    }
}

/// Uses the same public photo sources and MeuLab FlightAware endpoint as the iPhone app.
@MainActor
final class VisionFlightEnrichmentService {
    static let shared = VisionFlightEnrichmentService()

    private var photos = VisionEnrichmentCache<VisionAircraftPhoto?>()
    private var flights = VisionEnrichmentCache<FlightAwareFlight?>()

    func photo(for aircraft: Aircraft) async -> VisionAircraftPhoto? {
        if let cached = photos.value(for: aircraft.hex) { return cached }

        let registration = aircraft.registration?.trimmingCharacters(in: .whitespacesAndNewlines)
        var lookup = VisionPhotoLookup.notFound
        if let registration, !registration.isEmpty {
            lookup = await planeSpotters(path: "reg", identifier: registration)
        }
        if lookup.photo == nil {
            lookup = lookup.merged(with: await planeSpotters(path: "hex", identifier: aircraft.hex))
        }
        if lookup.photo == nil {
            lookup = lookup.merged(with: await openSky(hex: aircraft.hex))
        }
        // A failure may clear in seconds: reopening the card should try again.
        if case .failed = lookup { return nil }
        photos.insert(lookup.photo, for: aircraft.hex)
        return lookup.photo
    }

    func flightAware(for aircraft: Aircraft) async throws -> FlightAwareFlight? {
        let ident = aircraft.callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !ident.isEmpty, ident != aircraft.hex.uppercased() else { return nil }
        if let cached = flights.value(for: ident) { return cached }

        let response: FlightAwareFlightResponse = try await VisionAPIClient.shared.fetch("api/flightaware/flight", query: [
            URLQueryItem(name: "ident", value: ident),
            URLQueryItem(name: "max_pages", value: "1")
        ])
        let result = response.data.flights?.first
        flights.insert(result, for: ident)
        return result
    }

    private func planeSpotters(path: String, identifier: String) async -> VisionPhotoLookup {
        let encoded = VisionQuery.pathSegment(identifier)
        guard let url = URL(string: "https://api.planespotters.net/pub/photos/\(path)/\(encoded)") else { return .notFound }
        var request = URLRequest(url: url)
        request.setValue("MeuLabApp/1.0 (+https://meulab.fun/contact)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .failed }
            if http.statusCode == 404 { return .notFound }
            guard (200...299).contains(http.statusCode),
                  let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return .failed }
            guard let first = (result["photos"] as? [[String: Any]])?.first else { return .notFound }
            let large = (first["thumbnail_large"] as? [String: Any])?["src"] as? String
            let small = (first["thumbnail"] as? [String: Any])?["src"] as? String
            guard let text = large ?? small, let photoURL = URL(string: text), photoURL.scheme == "https" else { return .notFound }
            return .found(VisionAircraftPhoto(url: photoURL, photographer: first["photographer"] as? String, source: "PlaneSpotters"))
        } catch {
            return .failed
        }
    }

    private func openSky(hex: String) async -> VisionPhotoLookup {
        guard let url = URL(string: "https://opensky-network.org/api/metadata/data/aircraft/icao24/\(hex.lowercased())/image") else { return .notFound }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 8
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return .failed }
        switch http.statusCode {
        case 200: return .found(VisionAircraftPhoto(url: url, photographer: nil, source: "OpenSky"))
        case 404: return .notFound
        default: return .failed
        }
    }
}
