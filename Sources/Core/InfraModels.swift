import Foundation

struct VisionAPIMetrics: Decodable, Sendable {
    let uptimeSeconds: Int
    let requestCount: Int
    let avgResponseMs: Double
    let cacheHits: Int
    let cacheMisses: Int
    enum CodingKeys: String, CodingKey {
        case uptimeSeconds = "uptime_seconds", requestCount = "request_count"
        case avgResponseMs = "avg_response_ms", cacheHits = "cache_hits", cacheMisses = "cache_misses"
    }
}

struct VisionDockerStatus: Decodable, Sendable { let containers: [VisionDockerContainer] }
struct VisionDockerContainer: Decodable, Sendable, Identifiable {
    let id: String
    let names: String
    let image: String
    let state: String
    let status: String
    let health: Health?
    struct Health: Decodable, Sendable {
        let status: String
        enum CodingKeys: String, CodingKey { case status = "Status" }
    }
    enum CodingKeys: String, CodingKey {
        case id = "ID", names = "Names", image = "Image", state = "State"
        case status = "Status", health = "Health"
    }
}

struct VisionSystemdStatus: Decodable, Sendable { let services: [VisionSystemdService] }
struct VisionSystemdService: Decodable, Sendable, Identifiable {
    let service: String
    let activeState: String
    let subState: String
    let description: String
    var id: String { service }
    enum CodingKeys: String, CodingKey {
        case service, description
        case activeState = "active_state", subState = "sub_state"
    }
}

struct VisionDiskHealth: Decodable, Sendable {
    let ok: Bool
    let devices: [Device]
    struct Device: Decodable, Sendable, Identifiable {
        let device: String
        let model: String?
        let healthPassed: Bool?
        let temperatureC: Double?
        let percentageUsed: Double?
        let mediaErrors: Double?
        var id: String { device }
        enum CodingKeys: String, CodingKey {
            case device, model
            case healthPassed = "health_passed", temperatureC = "temperature_c"
            case percentageUsed = "percentage_used", mediaErrors = "media_errors"
        }
    }
}
