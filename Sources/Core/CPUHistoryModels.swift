import Foundation

struct VisionCPUHistory: Decodable, Sendable {
    let cpu: CPU
    struct CPU: Decodable, Sendable {
        let average: Double
        let peak: Double
        let minimum: Double
        let dataPoints: [Point]
    }
    struct Point: Decodable, Sendable {
        let timestamp: String
        let usage: Double
    }
}
