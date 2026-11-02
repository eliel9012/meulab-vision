import Foundation
import Synchronization
@testable import MeuLabVision

/// `URLProtocol` mock. Cada `MockAPI` usa host próprio, então testes paralelos
/// do Swift Testing não compartilham handler nem histórico de requests.
final class MockURLProtocol: URLProtocol {
    typealias Handler = @Sendable (URLRequest) throws -> (Int, Data)

    private static let handlers = Mutex<[String: Handler]>([:])
    private static let requests = Mutex<[String: [URLRequest]]>([:])

    static func register(host: String, handler: @escaping Handler) {
        handlers.withLock { $0[host] = handler }
    }

    static func recorded(host: String) -> [URLRequest] {
        requests.withLock { $0[host] ?? [] }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let host = request.url?.host() ?? ""
        Self.requests.withLock { $0[host, default: []].append(request) }
        guard let handler = Self.handlers.withLock({ $0[host] }), let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        do {
            let (status, data) = try handler(request)
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

struct MockAPI {
    let host: String
    let client: VisionAPIClient

    /// `routes`: path (sem query) → (status, fixture). Path ausente → 404.
    init(token: String = "test-token", routes: [String: (Int, String)]) {
        let host = "mock-\(UUID().uuidString.lowercased()).test"
        let table = routes.mapValues { status, fixture in (status, Fixture.data(fixture)) }
        MockURLProtocol.register(host: host) { request in
            table[request.url?.path() ?? ""] ?? (404, Data())
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        self.host = host
        client = VisionAPIClient(baseURL: URL(string: "https://\(host)")!, token: token,
                                 session: URLSession(configuration: configuration))
    }

    var requests: [URLRequest] { MockURLProtocol.recorded(host: host) }
}

enum Fixture {
    private final class Token {}

    static func data(_ name: String) -> Data {
        guard !name.isEmpty else { return Data() }
        let bundle = Bundle(for: Token.self)
        guard let url = bundle.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            fatalError("Fixture ausente: \(name).json")
        }
        return data
    }

    static func decode<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
        try JSONDecoder().decode(T.self, from: data(name))
    }
}
