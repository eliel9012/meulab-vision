import Foundation

public struct SystemStatus: Codable, Equatable, Sendable {
    public let timestamp: String
    public let hostname: String
    public let location: String
    public let uptime: Uptime?
    public let cpu: CPUStatus?
    public let memory: MemoryStatus?
    public let disk: DiskStatus?
    public let wifi: WiFiStatus?

    public init(timestamp: String, hostname: String, location: String, uptime: Uptime?, cpu: CPUStatus?, memory: MemoryStatus?, disk: DiskStatus?, wifi: WiFiStatus?) {
        self.timestamp = timestamp
        self.hostname = hostname
        self.location = location
        self.uptime = uptime
        self.cpu = cpu
        self.memory = memory
        self.disk = disk
        self.wifi = wifi
    }
}

public struct Uptime: Codable, Equatable, Sendable {
    public let seconds: Int
    public let formatted: String
    public let days: Int
    public let hours: Int
    public let minutes: Int

    public init(seconds: Int, formatted: String, days: Int, hours: Int, minutes: Int) {
        self.seconds = seconds
        self.formatted = formatted
        self.days = days
        self.hours = hours
        self.minutes = minutes
    }
}

public struct CPUStatus: Codable, Equatable, Sendable {
    public let usagePercent: Double?
    public let load1min: Double?
    public let load5min: Double?
    public let load15min: Double?
    public let temperatureC: Double?
    public let cores: Int?
    public let error: String?

    enum CodingKeys: String, CodingKey {
        case usagePercent = "usage_percent"
        case load1min = "load_1min"
        case load5min = "load_5min"
        case load15min = "load_15min"
        case temperatureC = "temperature_c"
        case cores, error
    }

    public var temperatureColor: String {
        guard let temp = temperatureC else { return "gray" }
        if temp < 50 { return "green" }
        if temp < 70 { return "orange" }
        return "red"
    }

    public init(usagePercent: Double?, load1min: Double?, load5min: Double?, load15min: Double?, temperatureC: Double?, cores: Int?, error: String?) {
        self.usagePercent = usagePercent
        self.load1min = load1min
        self.load5min = load5min
        self.load15min = load15min
        self.temperatureC = temperatureC
        self.cores = cores
        self.error = error
    }
}

public struct MemoryStatus: Codable, Equatable, Sendable {
    public let totalMb: Int?
    public let usedMb: Int?
    public let availableMb: Int?
    public let usedPercent: Double?
    public let error: String?

    enum CodingKeys: String, CodingKey {
        case totalMb = "total_mb"
        case usedMb = "used_mb"
        case availableMb = "available_mb"
        case usedPercent = "used_percent"
        case error
    }

    public init(totalMb: Int?, usedMb: Int?, availableMb: Int?, usedPercent: Double?, error: String?) {
        self.totalMb = totalMb
        self.usedMb = usedMb
        self.availableMb = availableMb
        self.usedPercent = usedPercent
        self.error = error
    }
}

public struct DiskStatus: Codable, Equatable, Sendable {
    public let totalGb: Double?
    public let usedGb: Double?
    public let availableGb: Double?
    public let usedPercent: Double?
    public let error: String?

    enum CodingKeys: String, CodingKey {
        case totalGb = "total_gb"
        case usedGb = "used_gb"
        case availableGb = "available_gb"
        case usedPercent = "used_percent"
        case error
    }

    public init(totalGb: Double?, usedGb: Double?, availableGb: Double?, usedPercent: Double?, error: String?) {
        self.totalGb = totalGb
        self.usedGb = usedGb
        self.availableGb = availableGb
        self.usedPercent = usedPercent
        self.error = error
    }
}

public struct WiFiStatus: Codable, Equatable, Sendable {
    public let ssid: String?
    public let qualityPercent: Int?
    public let signalDbm: Int?

    enum CodingKeys: String, CodingKey {
        case ssid
        case qualityPercent = "quality_percent"
        case signalDbm = "signal_dbm"
    }

    public init(ssid: String?, qualityPercent: Int?, signalDbm: Int?) {
        self.ssid = ssid
        self.qualityPercent = qualityPercent
        self.signalDbm = signalDbm
    }
}
