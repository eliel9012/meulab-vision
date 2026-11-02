import Foundation

struct VisionSystemAnalytics: Decodable, Sendable {
    let cpu: CPU
    let memory: Memory
    let disk: Disk
    let temperature: Temperature
    let uptime: Uptime?

    struct CPU: Decodable, Sendable {
        let dataPoints: [Point]
        let average: Double
        let peak: Double
        let minimum: Double?
        struct Point: Decodable, Sendable { let timestamp: String; let usage: Double }
    }
    struct Memory: Decodable, Sendable {
        let dataPoints: [Point]
        let averageUsage: Double
        let peakUsage: Double
        let minimumAvailable: Double?
        struct Point: Decodable, Sendable { let timestamp: String; let usedPercent: Double }
    }
    struct Disk: Decodable, Sendable {
        let dataPoints: [Point]
        let averageUsage: Double
        let peakUsage: Double
        let growthRate: Double?
        struct Point: Decodable, Sendable { let timestamp: String; let usedPercent: Double }
    }
    struct Temperature: Decodable, Sendable {
        let dataPoints: [Point]
        let average: Double
        let peak: Double
        let minimum: Double?
        struct Point: Decodable, Sendable { let timestamp: String; let temperature: Double }
    }
    struct Uptime: Decodable, Sendable { let current: Int; let average: Int; let reboots: Int }
}

struct VisionADSBAnalytics: Decodable, Sendable {
    let totalFlights: Int
    let uniqueAircraft: Int
    let hourlyStats: [Hour]
    let dailyStats: [Day]?
    let topAircraftTypes: [AircraftType]?
    let topRoutes: [Route]?
    let altitudeDistribution: [Altitude]?
    struct Hour: Decodable, Sendable { let hour: Int; let flightCount: Int }
    struct Day: Decodable, Sendable { let date: String; let flightCount: Int; let uniqueAircraft: Int }
    struct AircraftType: Decodable, Sendable { let type: String; let count: Int; let percentage: Double }
    struct Route: Decodable, Sendable { let origin: String; let destination: String; let count: Int; let percentage: Double }
    struct Altitude: Decodable, Sendable { let range: String; let count: Int; let percentage: Double }
}
