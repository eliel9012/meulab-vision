import Foundation

struct VisionProcessList: Decodable, Sendable { let items: [VisionProcess] }
struct VisionProcess: Decodable, Sendable, Identifiable {
    let pid: Int
    let command: String
    let cpuPercent: Double
    let memPercent: Double
    var id: Int { pid }
    enum CodingKeys: String, CodingKey {
        case pid, command
        case cpuPercent = "cpu_percent", memPercent = "mem_percent"
    }
}
struct VisionPartitionList: Decodable, Sendable { let partitions: [VisionPartition] }
struct VisionPartition: Decodable, Sendable, Identifiable {
    let mount: String
    let filesystem: String
    let usedPercent: String
    var id: String { mount }
    enum CodingKeys: String, CodingKey { case mount, filesystem, usedPercent = "used_percent" }
}
struct VisionNetworkStats: Decodable, Sendable { let interfaces: [VisionNetworkInterface] }
struct VisionNetworkInterface: Decodable, Sendable, Identifiable {
    let iface: String
    let rxBytes: Int64
    let txBytes: Int64
    var id: String { iface }
    enum CodingKeys: String, CodingKey { case iface, rxBytes = "rx_bytes", txBytes = "tx_bytes" }
}
struct VisionACARSSummary: Decodable, Sendable {
    let today: Today
    let lastHour: Int
    struct Today: Decodable, Sendable { let messages: Int; let flights: Int; let aircraft: Int }
    enum CodingKeys: String, CodingKey { case today, lastHour = "last_hour" }
}
struct VisionACARSList: Decodable, Sendable { let messages: [VisionACARSMessage] }
struct VisionACARSMessage: Decodable, Sendable, Identifiable {
    let id: Int
    let flight: String?
    let tail: String?
    let label: String?
    let text: String?
    let time: String
}
