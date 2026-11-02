import Foundation
import RealityKit
import simd

// Pure SharePlay sync model: no GroupSession here, so everything is unit-testable.

/// Yaw / uniform scale / offset of the manipulated radar table (`scene.root`).
struct RadarTableTransform: Codable, Sendable, Equatable {
    static let identity = RadarTableTransform(yawRadians: 0, scale: 1, offset: .zero)

    let yawRadians: Float
    let scale: Float
    let offset: SIMD3<Float>

    /// Normalises every field: yaw wrapped to (-π, π], scale clamped to the
    /// manipulation range, offset clamped to the drag limits, non-finite → identity.
    init(yawRadians: Float, scale: Float, offset: SIMD3<Float>) {
        self.yawRadians = Self.wrap(yawRadians.isFinite ? yawRadians : 0)
        let range = RadarTableManipulation.scaleRange
        self.scale = scale.isFinite ? min(range.upperBound, max(range.lowerBound, scale)) : 1
        let safe = SIMD3<Float>(
            offset.x.isFinite ? offset.x : 0,
            offset.y.isFinite ? offset.y : 0,
            offset.z.isFinite ? offset.z : 0
        )
        self.offset = [
            min(RadarTableDrag.limitX, max(-RadarTableDrag.limitX, safe.x)),
            min(RadarTableDrag.limitY, max(-RadarTableDrag.limitY, safe.y)),
            min(RadarTableDrag.limitX, max(-RadarTableDrag.limitX, safe.z))
        ]
    }

    /// Maps an entity transform (any rotation) onto the level-table model.
    init(_ transform: Transform) {
        let yaw = RadarTableManipulation.yawOnly(transform.rotation)
        let angle = 2 * atan2(yaw.imag.y, yaw.real)
        let uniform = (transform.scale.x + transform.scale.y + transform.scale.z) / 3
        self.init(yawRadians: angle, scale: uniform, offset: transform.translation)
    }

    var transform: Transform {
        Transform(
            scale: SIMD3(repeating: scale),
            rotation: simd_quatf(angle: yawRadians, axis: [0, 1, 0]),
            translation: offset
        )
    }

    func isApproximatelyEqual(to other: RadarTableTransform,
                              angleTolerance: Float = 0.005,
                              scaleTolerance: Float = 0.002,
                              offsetTolerance: Float = 0.001) -> Bool {
        abs(Self.wrap(yawRadians - other.yawRadians)) <= angleTolerance
            && abs(scale - other.scale) <= scaleTolerance
            && simd_length(offset - other.offset) <= offsetTolerance
    }

    static func wrap(_ angle: Float) -> Float {
        var value = angle.truncatingRemainder(dividingBy: 2 * .pi)
        if value <= -.pi { value += 2 * .pi }
        if value > .pi { value -= 2 * .pi }
        return value
    }

    private enum CodingKeys: String, CodingKey { case yawRadians, scale, offset }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            yawRadians: container.decode(Float.self, forKey: .yawRadians),
            scale: container.decode(Float.self, forKey: .scale),
            offset: container.decode(SIMD3<Float>.self, forKey: .offset)
        )
    }
}

/// Last-writer-wins stamp. Ties on time break on the author id, so every
/// participant converges on the same winner.
struct RadarSyncStamp: Codable, Sendable, Hashable, Comparable {
    let time: TimeInterval
    let author: UUID

    static func < (lhs: RadarSyncStamp, rhs: RadarSyncStamp) -> Bool {
        lhs.time != rhs.time ? lhs.time < rhs.time : lhs.author.uuidString < rhs.author.uuidString
    }
}

/// Versioned wire message. Unknown (newer) versions are dropped by `RadarSyncCodec`.
struct RadarSyncMessage: Codable, Sendable, Equatable {
    static let currentVersion = 1

    enum Payload: Codable, Sendable, Equatable {
        case selection(hex: String?)
        case tableTransform(RadarTableTransform)
        /// Late joiner asks the others for their current state.
        case requestState
        /// Opaque ARKit `SharedCoordinateSpaceProvider` data, relayed as-is.
        case coordinateSpace(data: Data, recipients: [UUID])
    }

    var version: Int = RadarSyncMessage.currentVersion
    let stamp: RadarSyncStamp
    let payload: Payload
}

enum RadarSyncCodec {
    private struct Header: Decodable { let version: Int }

    static func encode(_ message: RadarSyncMessage) throws -> Data {
        try JSONEncoder().encode(message)
    }

    /// nil for garbage, a newer protocol version, or an unknown payload.
    static func decode(_ data: Data) -> RadarSyncMessage? {
        let decoder = JSONDecoder()
        guard let header = try? decoder.decode(Header.self, from: data),
              header.version >= 1, header.version <= RadarSyncMessage.currentVersion else { return nil }
        return try? decoder.decode(RadarSyncMessage.self, from: data)
    }
}

enum RadarSyncAction: Equatable, Sendable {
    case applySelection(String?)
    case applyTransform(RadarTableTransform)
    case sendState
    case coordinateSpace(data: Data, recipients: [UUID])
}

/// LWW replica of the shared radar state (selection + table transform).
///
/// Anti-echo: a received value is stored before it is applied locally, so the
/// resulting local change (`selectedHex.didSet`, manipulation event) compares
/// equal and produces no message; messages authored by `localID` are ignored.
struct RadarSyncEngine: Sendable {
    struct Stamped<Value: Sendable & Equatable>: Sendable, Equatable {
        let value: Value
        let stamp: RadarSyncStamp
    }

    static let transformMinInterval: TimeInterval = 0.1

    let localID: UUID
    private(set) var selection: Stamped<String?>?
    private(set) var transform: Stamped<RadarTableTransform>?
    private var lastTransformSentAt: TimeInterval = -.infinity
    private var transformNeedsReliableFlush = false

    init(localID: UUID = UUID()) {
        self.localID = localID
    }

    /// Monotonic local stamp: never behind anything already seen (clock skew).
    mutating func nextStamp(now: TimeInterval) -> RadarSyncStamp {
        let latest = max(selection?.stamp.time ?? -.infinity, transform?.stamp.time ?? -.infinity)
        return RadarSyncStamp(time: max(now, latest + 0.001), author: localID)
    }

    mutating func localSelection(_ hex: String?, now: TimeInterval) -> RadarSyncMessage? {
        if let selection, selection.value == hex { return nil }
        let stamp = nextStamp(now: now)
        selection = Stamped(value: hex, stamp: stamp)
        return RadarSyncMessage(stamp: stamp, payload: .selection(hex: hex))
    }

    /// Throttled (unreliable channel); call `flushTransform` after the gesture settles.
    mutating func localTransform(_ value: RadarTableTransform, now: TimeInterval) -> RadarSyncMessage? {
        if let transform, transform.value.isApproximatelyEqual(to: value) { return nil }
        let stamp = nextStamp(now: now)
        transform = Stamped(value: value, stamp: stamp)
        transformNeedsReliableFlush = true
        guard now - lastTransformSentAt >= Self.transformMinInterval else { return nil }
        lastTransformSentAt = now
        return RadarSyncMessage(stamp: stamp, payload: .tableTransform(value))
    }

    /// Final transform to send reliably once local manipulation stops.
    mutating func flushTransform(now: TimeInterval) -> RadarSyncMessage? {
        guard transformNeedsReliableFlush, let transform, transform.stamp.author == localID else { return nil }
        transformNeedsReliableFlush = false
        lastTransformSentAt = now
        return RadarSyncMessage(stamp: transform.stamp, payload: .tableTransform(transform.value))
    }

    mutating func receive(_ message: RadarSyncMessage) -> RadarSyncAction? {
        guard message.version <= RadarSyncMessage.currentVersion,
              message.stamp.author != localID else { return nil }
        switch message.payload {
        case .selection(let hex):
            if let selection, message.stamp <= selection.stamp { return nil }
            let changed = selection?.value != hex
            selection = Stamped(value: hex, stamp: message.stamp)
            return changed ? .applySelection(hex) : nil
        case .tableTransform(let value):
            if let transform, message.stamp <= transform.stamp { return nil }
            let changed = !(transform?.value.isApproximatelyEqual(to: value) ?? false)
            transform = Stamped(value: value, stamp: message.stamp)
            transformNeedsReliableFlush = false
            return changed ? .applyTransform(value) : nil
        case .requestState:
            return .sendState
        case .coordinateSpace(let data, let recipients):
            return .coordinateSpace(data: data, recipients: recipients)
        }
    }

    /// Seeds a selection nobody explicitly made (auto-select, or chosen before the
    /// session) with the lowest stamp so any explicit group selection beats it;
    /// ties between seeds converge by author.
    mutating func seedSelection(_ hex: String?) {
        guard selection == nil, let hex else { return }
        selection = Stamped(value: hex, stamp: RadarSyncStamp(time: 0, author: localID))
    }

    /// Current state with the original stamps, for a participant that asked.
    func snapshot() -> [RadarSyncMessage] {
        var messages: [RadarSyncMessage] = []
        if let selection {
            messages.append(RadarSyncMessage(stamp: selection.stamp, payload: .selection(hex: selection.value)))
        }
        if let transform {
            messages.append(RadarSyncMessage(stamp: transform.stamp, payload: .tableTransform(transform.value)))
        }
        return messages
    }
}
