import Foundation

// MARK: - Fire Stick

public struct FirestickDevicesResponse: Codable, Equatable, Sendable {
    public let ok: Bool
    public let devices: [FirestickDevice]
    public let defaultId: String?

    enum CodingKeys: String, CodingKey {
        case ok, devices
        case defaultId = "default_id"
    }

    public init(ok: Bool, devices: [FirestickDevice], defaultId: String?) {
        self.ok = ok
        self.devices = devices
        self.defaultId = defaultId
    }
}

public struct FirestickDevice: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let ip: String
    public let port: Int
    public let serial: String?

    public init(id: String, name: String, ip: String, port: Int, serial: String?) {
        self.id = id
        self.name = name
        self.ip = ip
        self.port = port
        self.serial = serial
    }
}

public struct FirestickStatusResponse: Codable, Equatable, Sendable {
    public let ok: Bool
    public let timestamp: String
    public let firestick: FirestickStatusPayload

    public init(ok: Bool, timestamp: String, firestick: FirestickStatusPayload) {
        self.ok = ok
        self.timestamp = timestamp
        self.firestick = firestick
    }
}

public struct FirestickStatusPayload: Codable, Equatable, Sendable {
    public let name: String
    public let ip: String
    public let port: Int
    public let serial: String
    public let tvOn: Bool?
    public let tvShowingFirestick: Bool?
    public let adb: FirestickAdb
    public let foregroundApp: FirestickForegroundApp?
    public let error: String?

    enum CodingKeys: String, CodingKey {
        case name, ip, port, serial, adb, error
        case tvOn = "tv_on"
        case tvShowingFirestick = "tv_showing_firestick"
        case foregroundApp = "foreground_app"
    }

    public init(name: String, ip: String, port: Int, serial: String, tvOn: Bool?, tvShowingFirestick: Bool?, adb: FirestickAdb, foregroundApp: FirestickForegroundApp?, error: String?) {
        self.name = name
        self.ip = ip
        self.port = port
        self.serial = serial
        self.tvOn = tvOn
        self.tvShowingFirestick = tvShowingFirestick
        self.adb = adb
        self.foregroundApp = foregroundApp
        self.error = error
    }
}

public struct FirestickAdb: Codable, Equatable, Sendable {
    public let installed: Bool
    public let deviceState: String?

    enum CodingKeys: String, CodingKey {
        case installed
        case deviceState = "device_state"
    }

    public init(installed: Bool, deviceState: String?) {
        self.installed = installed
        self.deviceState = deviceState
    }
}

public struct FirestickForegroundApp: Codable, Equatable, Sendable {
    public let component: String?
    public let package: String?
    public let activity: String?

    public init(component: String?, package: String?, activity: String?) {
        self.component = component
        self.package = package
        self.activity = activity
    }
}

public struct FirestickScreenshotKeyResponse: Codable, Equatable, Sendable {
    public let ok: Bool
    public let id: String
    public let name: String
    public let serial: String
    public let ttlSeconds: Int
    public let url: String
    public let publicUrl: String?

    enum CodingKeys: String, CodingKey {
        case ok, id, name, serial, url
        case ttlSeconds = "ttl_seconds"
        case publicUrl = "public_url"
    }

    public init(ok: Bool, id: String, name: String, serial: String, ttlSeconds: Int, url: String, publicUrl: String?) {
        self.ok = ok
        self.id = id
        self.name = name
        self.serial = serial
        self.ttlSeconds = ttlSeconds
        self.url = url
        self.publicUrl = publicUrl
    }
}

public struct FirestickDeviceStatus: Identifiable, Equatable, Sendable {
    public let device: FirestickDevice
    public let status: FirestickStatusResponse

    public var id: String { device.id }

    public init(device: FirestickDevice, status: FirestickStatusResponse) {
        self.device = device
        self.status = status
    }
}

