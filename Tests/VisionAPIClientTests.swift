import Foundation
import Testing
@testable import MeuLabVision

@Suite("VisionAPIClient")
struct VisionAPIClientTests {
    @Test func fetchSendsAuthHeadersAndDecodes() async throws {
        let api = MockAPI(token: "abc", routes: ["/api/alerts/rules": (200, "alerts_rules")])
        let rules: [VisionAlertRule] = try await api.client.fetch("api/alerts/rules")
        #expect(rules.map(\.id) == ["r1", "r2"])
        let request = try #require(api.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "X-API-Token") == "abc")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "MeuLabApp/1.0")
        #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
    }

    @Test func postUsesPOST() async throws {
        let api = MockAPI(routes: ["/api/alerts/triggers/t%2F1/ack": (200, "alert_trigger")])
        let id = VisionQuery.pathSegment("t/1")
        let trigger: VisionAlertTrigger = try await api.client.post("api/alerts/triggers/\(id)/ack")
        #expect(trigger.acknowledged)
        #expect(api.requests.first?.httpMethod == "POST")
    }

    @Test func httpErrorSurfacesStatus() async {
        let api = MockAPI(routes: ["/api/metrics": (503, "")])
        await #expect(throws: VisionAPIError.http(503)) {
            let _: VisionAPIMetrics = try await api.client.fetch("api/metrics")
        }
    }

    @Test func missingRouteIs404() async {
        let api = MockAPI(routes: [:])
        await #expect(throws: VisionAPIError.http(404)) {
            let _: VisionAPIMetrics = try await api.client.fetch("api/nada")
        }
    }

    @Test func queryItemsAreEncoded() throws {
        let client = VisionAPIClient(baseURL: URL(string: "https://example.test")!, token: "t")
        let url = try client.url("api/acars/search", query: [
            URLQueryItem(name: "q", value: "PR-XBA & G3+1/2 #x"),
            URLQueryItem(name: "details", value: "1")
        ])
        #expect(url.absoluteString == "https://example.test/api/acars/search?q=PR-XBA%20%26%20G3%2B1%2F2%20%23x&details=1")
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.queryItems?.first?.value == "PR-XBA & G3+1/2 #x")
    }

    @Test func literalQueryInPathIsPreservedAndMerged() throws {
        let client = VisionAPIClient(baseURL: URL(string: "https://example.test")!, token: "t")
        #expect(try client.url("api/system/processes?limit=8").absoluteString
                == "https://example.test/api/system/processes?limit=8")
        #expect(try client.url("api/docker/status?health=1", query: [URLQueryItem(name: "a", value: "b c")]).absoluteString
                == "https://example.test/api/docker/status?health=1&a=b%20c")
    }

    @Test func fetchTextReturnsBodyAndSendsQuery() async throws {
        let api = MockAPI(routes: ["/api/docker/logs": (200, "infra_metrics")])
        let text = try await api.client.fetchText("api/docker/logs", query: [URLQueryItem(name: "container", value: "readsb")])
        #expect(text.contains("uptime_seconds"))
        #expect(api.requests.first?.url?.query() == "container=readsb")
    }

    @Test func secretsPrefersAPITokenAndFallsBack() throws {
        let first = try #require(VisionAPIClient.fromSecrets(["API_BASE_URL": "https://a.test", "API_TOKEN": "x", "MEULAB_API_TOKEN": "y"]))
        #expect(first.token == "x")
        let fallback = try #require(VisionAPIClient.fromSecrets(["API_BASE_URL": "https://a.test", "API_TOKEN": "", "MEULAB_API_TOKEN": "y"]))
        #expect(fallback.token == "y")
        #expect(VisionAPIClient.fromSecrets(["API_TOKEN": "x"]) == nil)
        #expect(VisionAPIClient.fromSecrets(["API_BASE_URL": "https://a.test"]) == nil)
    }

    @Test func secretsRejectsAnythingButHTTPS() {
        #expect(VisionAPIClient.fromSecrets(["API_BASE_URL": "http://a.test", "API_TOKEN": "x"]) == nil)
        #expect(VisionAPIClient.fromSecrets(["API_BASE_URL": "a.test", "API_TOKEN": "x"]) == nil)
        #expect(VisionAPIClient.fromSecrets(["API_BASE_URL": "HTTPS://a.test", "API_TOKEN": "x"]) != nil)
    }

    @Test func pathCannotEscapeTheAPIHost() throws {
        let client = VisionAPIClient(baseURL: URL(string: "https://example.test")!, token: "t")
        #expect(throws: VisionAPIError.invalidURL) { try client.url("/evil.test/steal") }
        #expect(throws: VisionAPIError.invalidURL) { try client.url("//evil.test/steal") }
        #expect(try client.url("api/ok").host() == "example.test")
    }

    @Test func redirectsOnlyStayOnTheSameOrigin() throws {
        let client = VisionAPIClient(baseURL: URL(string: "https://example.test")!, token: "t")
        #expect(client.isSameOrigin(URL(string: "https://EXAMPLE.test/outra")!))
        #expect(!client.isSameOrigin(URL(string: "https://evil.test/outra")!))
        #expect(!client.isSameOrigin(URL(string: "http://example.test/outra")!))
        #expect(!client.isSameOrigin(URL(string: "https://example.test:8443/outra")!))
    }
}
