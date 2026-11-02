import Foundation
import RealityKit
import Testing
@testable import MeuLabVision

@Suite("Fase 5B · SharePlay radar sync (pure logic)")
struct Fase5SharePlayTests {
    private let alice = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
    private let bob = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!

    private func message(_ payload: RadarSyncMessage.Payload, at time: TimeInterval, by author: UUID) -> RadarSyncMessage {
        RadarSyncMessage(stamp: RadarSyncStamp(time: time, author: author), payload: payload)
    }

    // MARK: Codec

    @Test("Every payload survives encode/decode")
    func codecRoundTrip() throws {
        let payloads: [RadarSyncMessage.Payload] = [
            .selection(hex: "e49406"),
            .selection(hex: nil),
            .tableTransform(RadarTableTransform(yawRadians: 0.7, scale: 1.1, offset: [0.05, -0.1, 0])),
            .requestState,
            .coordinateSpace(data: Data([1, 2, 3]), recipients: [alice])
        ]
        for payload in payloads {
            let original = message(payload, at: 42, by: alice)
            let decoded = RadarSyncCodec.decode(try RadarSyncCodec.encode(original))
            #expect(decoded == original)
        }
    }

    @Test("Future versions and garbage are dropped")
    func codecRejects() throws {
        var future = message(.selection(hex: "abc"), at: 1, by: alice)
        future.version = RadarSyncMessage.currentVersion + 1
        #expect(RadarSyncCodec.decode(try RadarSyncCodec.encode(future)) == nil)
        #expect(RadarSyncCodec.decode(Data("not json".utf8)) == nil)
        #expect(RadarSyncCodec.decode(Data(#"{"version":1}"#.utf8)) == nil)
    }

    // MARK: Last-writer-wins

    @Test("Older remote writes lose; newer ones win")
    func lastWriterWins() {
        var engine = RadarSyncEngine(localID: alice)
        let r101 = engine.receive(message(.selection(hex: "new"), at: 10, by: bob))
        #expect(r101 == .applySelection("new"))
        let r102 = engine.receive(message(.selection(hex: "old"), at: 5, by: bob))
        #expect(r102 == nil)
        #expect(engine.selection?.value == "new")
        let r103 = engine.receive(message(.selection(hex: "newer"), at: 11, by: bob))
        #expect(r103 == .applySelection("newer"))
    }

    @Test("Equal timestamps break on author id, identically everywhere")
    func tieBreak() {
        let low = RadarSyncStamp(time: 5, author: alice)
        let high = RadarSyncStamp(time: 5, author: bob)
        #expect(low < high)
        var engine = RadarSyncEngine(localID: UUID())
        _ = engine.receive(message(.selection(hex: "b"), at: 5, by: bob))
        let r104 = engine.receive(message(.selection(hex: "a"), at: 5, by: alice))
        #expect(r104 == nil)
        #expect(engine.selection?.value == "b")
    }

    @Test("Local stamps never fall behind a value already seen (clock skew)")
    func monotonicStamp() {
        var engine = RadarSyncEngine(localID: alice)
        _ = engine.receive(message(.selection(hex: "x"), at: 1_000, by: bob))
        let local = engine.localSelection("y", now: 10)
        #expect(local != nil)
        #expect((local?.stamp.time ?? 0) > 1_000)
    }

    // MARK: Anti-echo

    @Test("Own messages are ignored")
    func ignoresOwnMessages() {
        var engine = RadarSyncEngine(localID: alice)
        let r105 = engine.receive(message(.selection(hex: "x"), at: 1, by: alice))
        #expect(r105 == nil)
        let r1 = engine.receive(message(.requestState, at: 1, by: alice))
        #expect(r1 == nil)
    }

    @Test("Applying a remote value does not re-broadcast it")
    func noEchoAfterApply() {
        var engine = RadarSyncEngine(localID: alice)
        _ = engine.receive(message(.selection(hex: "x"), at: 1, by: bob))
        let r2 = engine.localSelection("x", now: 2)
        #expect(r2 == nil)
        let remote = RadarTableTransform(yawRadians: 1, scale: 1, offset: .zero)
        _ = engine.receive(message(.tableTransform(remote), at: 3, by: bob))
        let r3 = engine.localTransform(remote, now: 4)
        #expect(r3 == nil)
        let r4 = engine.flushTransform(now: 5)
        #expect(r4 == nil)
        let r5 = engine.localSelection("y", now: 6)
        #expect(r5?.payload == .selection(hex: "y"))
    }

    @Test("Duplicate remote value produces no action")
    func duplicateRemoteValue() {
        var engine = RadarSyncEngine(localID: alice)
        _ = engine.receive(message(.selection(hex: "x"), at: 1, by: bob))
        let r106 = engine.receive(message(.selection(hex: "x"), at: 2, by: bob))
        #expect(r106 == nil)
    }

    // MARK: Transform throttle / flush / snapshot

    @Test("Transform updates are throttled, then flushed reliably")
    func throttleAndFlush() {
        var engine = RadarSyncEngine(localID: alice)
        let first = RadarTableTransform(yawRadians: 0.1, scale: 1, offset: .zero)
        let second = RadarTableTransform(yawRadians: 0.2, scale: 1, offset: .zero)
        let r6 = engine.localTransform(first, now: 100)
        #expect(r6 != nil)
        let r7 = engine.localTransform(second, now: 100.05)
        #expect(r7 == nil)
        let flush = engine.flushTransform(now: 100.3)
        #expect(flush?.payload == .tableTransform(second))
        let r8 = engine.flushTransform(now: 100.4)
        #expect(r8 == nil)
    }

    @Test("Snapshot answers requestState with original stamps")
    func snapshot() {
        var engine = RadarSyncEngine(localID: alice)
        let r9 = engine.receive(message(.requestState, at: 1, by: bob))
        #expect(r9 == .sendState)
        #expect(engine.snapshot().isEmpty)
        let selection = engine.localSelection("x", now: 10)
        _ = engine.localTransform(.identity, now: 11)
        let snapshot = engine.snapshot()
        #expect(snapshot.count == 2)
        #expect(snapshot.first?.stamp == selection?.stamp)
    }

    // MARK: Transform mapping

    @Test("Entity transform maps to yaw/scale and back")
    func transformRoundTrip() {
        let entity = Transform(scale: SIMD3(repeating: 1.1),
                               rotation: simd_quatf(angle: 0.8, axis: [0, 1, 0]),
                               translation: [0.05, 0.1, 0])
        let model = RadarTableTransform(entity)
        #expect(abs(model.yawRadians - 0.8) < 0.001)
        #expect(abs(model.scale - 1.1) < 0.001)
        #expect(RadarTableTransform(model.transform).isApproximatelyEqual(to: model))
    }

    @Test("Yaw wraps, scale and offset clamp, non-finite becomes identity")
    func normalisation() {
        let wrapped = RadarTableTransform(yawRadians: 3 * .pi, scale: 9, offset: [1, -1, 1])
        #expect(abs(abs(wrapped.yawRadians) - .pi) < 0.001)
        #expect(wrapped.scale == RadarTableManipulation.scaleRange.upperBound)
        #expect(wrapped.offset == [RadarTableDrag.limitX, -RadarTableDrag.limitY, RadarTableDrag.limitX])
        let bad = RadarTableTransform(yawRadians: .nan, scale: .infinity, offset: [.nan, 0, 0])
        #expect(bad == .identity)
    }

    @Test("Tilt is discarded: only yaw survives")
    func tiltDiscarded() {
        let tilted = Transform(rotation: simd_quatf(angle: 0.5, axis: [1, 0, 0]) * simd_quatf(angle: 0.4, axis: [0, 1, 0]))
        let model = RadarTableTransform(tilted)
        let rotated = model.transform.rotation.act([0, 1, 0])
        #expect(abs(rotated.y - 1) < 0.001)
    }
}
