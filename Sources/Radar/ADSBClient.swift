import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

protocol ADSBProviding: Sendable {
    func fetch() async throws -> Data
}

enum ADSBNetworkError: LocalizedError {
    case unexpectedStatus(Int)
    case invalidResponse
    case payloadTooLarge

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status): return "O radar respondeu HTTP \(status)."
        case .invalidResponse: return "Resposta HTTP inválida."
        case .payloadTooLarge: return "O JSON do radar excedeu o limite de segurança (8 MB)."
        }
    }
}

struct ADSBClient: ADSBProviding {
    static let endpoint = URL(string: "https://radar.meulab.fun/data/aircraft.json")!
    let url: URL
    let session: URLSession

    init(url: URL = endpoint, session: URLSession = .shared) {
        self.url = url
        self.session = session
    }

    func fetch() async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw ADSBNetworkError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else { throw ADSBNetworkError.unexpectedStatus(response.statusCode) }
        guard data.count <= 8 * 1_024 * 1_024 else { throw ADSBNetworkError.payloadTooLarge }
        return data
    }
}
