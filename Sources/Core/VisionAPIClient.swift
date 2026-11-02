import Foundation

enum VisionAPIError: LocalizedError, Equatable, Sendable {
    case missingConfiguration, invalidURL, http(Int)
    var errorDescription: String? {
        switch self {
        case .missingConfiguration: "Configuração da API ausente. Adicione Secrets.plist ao projeto."
        case .invalidURL: "URL da API inválida."
        case .http(let code): "API respondeu HTTP \(code)."
        }
    }
}

/// Cliente único do backend MeuLab. `Secrets.plist` é lido uma vez (`shared`);
/// testes criam instâncias próprias com `URLSession` configurada com `URLProtocol` mock.
/// Rede e decode rodam fora do main actor (`@concurrent`).
struct VisionAPIClient: Sendable {
    let baseURL: URL
    let token: String
    let session: URLSession

    init(baseURL: URL, token: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.token = token
        self.session = session
    }

    /// Instância compartilhada configurada pelo `Secrets.plist` do bundle.
    static var shared: VisionAPIClient {
        get throws(VisionAPIError) { try configured.get() }
    }

    private static let configured: Result<VisionAPIClient, VisionAPIError> = {
        guard let client = fromSecrets(in: .main) else { return .failure(.missingConfiguration) }
        return .success(client)
    }()

    static func fromSecrets(in bundle: Bundle, session: URLSession = .shared) -> VisionAPIClient? {
        guard let path = bundle.path(forResource: "Secrets", ofType: "plist"),
              let values = NSDictionary(contentsOfFile: path) as? [String: Any] else { return nil }
        return fromSecrets(values, session: session)
    }

    static func fromSecrets(_ values: [String: Any], session: URLSession = .shared) -> VisionAPIClient? {
        guard let base = values["API_BASE_URL"] as? String,
              let url = URL(string: base),
              url.scheme?.lowercased() == "https", url.host() != nil, // o token nunca trafega em claro
              let token = [values["API_TOKEN"] as? String, values["MEULAB_API_TOKEN"] as? String]
                .compactMap({ $0 }).first(where: { !$0.isEmpty }) else { return nil }
        return VisionAPIClient(baseURL: url, token: token, session: session)
    }

    /// Monta `baseURL/path` + query. `path` pode trazer query literal já codificada;
    /// `query` é codificada via `URLComponents` (inclui `&`, `=`, `+`, `#` nos valores).
    /// Recusa `path` que troque de host (`/evil.test/x` viraria `//evil.test/x`): o token
    /// só pode ir para `baseURL`.
    func url(_ path: String, query: [URLQueryItem] = []) throws(VisionAPIError) -> URL {
        guard !path.hasPrefix("/"),
              let base = URL(string: "/\(path)", relativeTo: baseURL)?.absoluteURL,
              isSameOrigin(base) else {
            throw .invalidURL
        }
        guard !query.isEmpty else { return base }
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            throw .invalidURL
        }
        components.percentEncodedQueryItems = (components.percentEncodedQueryItems ?? [])
            + query.map(VisionQuery.encoded)
        guard let url = components.url else { throw .invalidURL }
        return url
    }

    @concurrent
    func fetch<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem] = [],
                                        as type: T.Type = T.self) async throws -> T {
        var request = authorizedRequest(try url(path, query: query))
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return try JSONDecoder().decode(T.self, from: await send(request))
    }

    @concurrent
    func post<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem] = [],
                                       as type: T.Type = T.self) async throws -> T {
        var request = authorizedRequest(try url(path, query: query))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try JSONDecoder().decode(T.self, from: await send(request))
    }

    @concurrent
    func fetchText(_ path: String, query: [URLQueryItem]) async throws -> String {
        let request = authorizedRequest(try url(path, query: query))
        return String(decoding: try await send(request), as: UTF8.self)
    }

    private func authorizedRequest(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(token, forHTTPHeaderField: "X-API-Token")
        request.setValue("MeuLabApp/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        return request
    }

    func isSameOrigin(_ url: URL) -> Bool {
        url.scheme?.lowercased() == baseURL.scheme?.lowercased()
            && url.host()?.lowercased() == baseURL.host()?.lowercased()
            && url.port == baseURL.port
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let guardDelegate = SameOriginRedirectGuard(client: self)
        let (data, response) = try await session.data(for: request, delegate: guardDelegate)
        guard let http = response as? HTTPURLResponse else { throw VisionAPIError.http(0) }
        guard (200...299).contains(http.statusCode) else { throw VisionAPIError.http(http.statusCode) }
        return data
    }
}

/// URLSession repete os headers (incluindo o token) ao seguir um redirect:
/// só deixa seguir dentro da mesma origem da API.
private final class SameOriginRedirectGuard: NSObject, URLSessionTaskDelegate {
    private let client: VisionAPIClient

    init(client: VisionAPIClient) {
        self.client = client
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        guard let url = request.url, client.isSameOrigin(url) else { return nil }
        return request
    }
}

enum VisionQuery {
    /// `urlQueryAllowed` sem os separadores que mudam o sentido da query.
    static let valueAllowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+#?/"))
    /// Segmento de path: sem `/` e `?`.
    static let pathSegmentAllowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?"))

    static func encoded(_ item: URLQueryItem) -> URLQueryItem {
        URLQueryItem(name: item.name.addingPercentEncoding(withAllowedCharacters: valueAllowed) ?? item.name,
                     value: item.value.map { $0.addingPercentEncoding(withAllowedCharacters: valueAllowed) ?? $0 })
    }

    static func pathSegment(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: pathSegmentAllowed) ?? value
    }
}
