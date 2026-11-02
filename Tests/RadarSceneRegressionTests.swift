import Foundation
import RealityKit
import Testing
@testable import MeuLabVision

private struct NoNetworkClient: ADSBProviding {
    func fetch() async throws -> Data { throw CancellationError() }
}

@MainActor
@Suite("Regressões da cena do radar")
struct RadarSceneRegressionTests {
    private func flights(_ hexes: String...) throws -> [Aircraft] {
        let items = hexes.map { #"{"hex":"\#($0)","lat":-20.5,"lon":-47.4,"alt_baro":3000,"seen_pos":1}"# }
        let json = #"{"now":1,"aircraft":[\#(items.joined(separator: ","))]}"#
        return try AircraftDecoder.decode(Data(json.utf8)).aircraft
    }

    private func modelEntities(under entity: Entity) -> [Entity] {
        let own = entity.components.has(ModelComponent.self) ? [entity] : []
        return own + entity.children.flatMap { modelEntities(under: $0) }
    }

    @Test func changingTheRadiusLeavesNoStaleBackgroundEntities() throws {
        let scene = RadarSceneController()
        let background = try #require(scene.root.findEntity(named: "radar-background"))
        scene.buildBackground(displayRadiusKilometers: 100)
        let count = background.children.count
        #expect(count >= 4)

        for radius in [150.0, 200, 250, 300] {
            scene.buildBackground(displayRadiusKilometers: radius)
            #expect(background.children.count == count)
        }
        #expect(background.children.filter { $0.name == "radar-rings" }.count == 1)
        #expect(background.children.filter { $0.name == "radar-edges" }.count == 1)
    }

    @Test func removedGrabberStaysGone() {
        #expect(RadarSceneController().root.findEntity(named: "radar-table-grabber") == nil)
    }

    @Test func entitiesCreatedLaterAreOccluded() throws {
        let scene = RadarSceneController()
        let settings = RadarSettings()
        scene.applyEnvironmentOcclusion(true)
        scene.reconcile(aircraft: try flights("a1"), selectedHex: nil, settings: settings, ageByHex: [:])

        let marker = try #require(scene.markerEntity(for: "a1"))
        let parts = modelEntities(under: marker)
        #expect(!parts.isEmpty)
        #expect(parts.allSatisfy { $0.components.has(EnvironmentBlendingComponent.self) })

        scene.buildBackground(displayRadiusKilometers: settings.displayRadiusKilometers + 50)
        let background = try #require(scene.root.findEntity(named: "radar-background"))
        #expect(modelEntities(under: background).allSatisfy { $0.components.has(EnvironmentBlendingComponent.self) })
    }

    @Test func nothingIsOccludedWhenDisabled() throws {
        let scene = RadarSceneController()
        scene.reconcile(aircraft: try flights("a1"), selectedHex: nil, settings: RadarSettings(), ageByHex: [:])
        #expect(modelEntities(under: scene.root).allSatisfy { !$0.components.has(EnvironmentBlendingComponent.self) })
    }

    @Test func hitScaleGrowsExistingAndNewMarkers() throws {
        let scene = RadarSceneController()
        func width(_ hex: String) throws -> Float {
            let marker = try #require(scene.markerEntity(for: hex))
            let shape = try #require(marker.components[CollisionComponent.self]?.shapes.first)
            return shape.bounds.extents.x
        }
        scene.reconcile(aircraft: try flights("a1"), selectedHex: nil, settings: RadarSettings(), ageByHex: [:])
        let base = try width("a1")
        scene.setMarkerHitScale(4)
        #expect(abs(try width("a1") - base * 4) < 1e-4)
        scene.reconcile(aircraft: try flights("a1", "b2"), selectedHex: nil, settings: RadarSettings(), ageByHex: [:])
        #expect(abs(try width("b2") - base * 4) < 1e-4)
    }

    @Test func holderBuildsOneController() {
        let holder = RadarSceneHolder()
        #expect(holder.controller === holder.controller)
    }

    @Test func pingBufferRejectsEmptySamples() throws {
        #expect(RadarPingAudio.buffer(samples: []) == nil)
        let buffer = try #require(RadarPingAudio.buffer(samples: [0.25, -0.5]))
        #expect(buffer.frameLength == 2)
        #expect(buffer.floatChannelData?[0][1] == -0.5)
    }

    @Test func positionAgesToleratesRepeatedHex() throws {
        let store = FlightStore(client: NoNetworkClient())
        store.aircraft = try flights("a1", "a1", "b2")
        let ages = store.positionAges(at: Date())
        #expect(Set(ages.keys) == ["a1", "b2"])
    }

    // MARK: - Shared downloads

    @Test func callersOfTheSameKeyShareOneFetch() async throws {
        let shared = RadarSharedFetch<Int, Int>(lifetime: 60)
        @MainActor final class Counter { var fetches = 0 }
        let counter = Counter()
        let now = Date(timeIntervalSince1970: 1_000)
        let callers = (0..<3).map { _ in
            Task { @MainActor in
                try await shared.value(for: 1, now: now) {
                    counter.fetches += 1
                    await Task.yield()
                    return counter.fetches
                }
            }
        }
        for caller in callers {
            #expect(try await caller.value == 1)
        }
        #expect(counter.fetches == 1)
    }

    @Test func sharedFetchRefetchesOnNewKeyAfterExpiryAndAfterFailure() async throws {
        struct Failure: Error {}
        let shared = RadarSharedFetch<Int, Int>(lifetime: 60)
        let start = Date(timeIntervalSince1970: 1_000)
        #expect(try await shared.value(for: 1, now: start) { 1 } == 1)
        #expect(try await shared.value(for: 1, now: start.addingTimeInterval(59)) { 2 } == 1)
        #expect(try await shared.value(for: 1, now: start.addingTimeInterval(60)) { 3 } == 3)
        #expect(try await shared.value(for: 2, now: start.addingTimeInterval(61)) { 4 } == 4)

        await #expect(throws: Failure.self) {
            try await shared.value(for: 3, now: start.addingTimeInterval(62)) { throw Failure() }
        }
        #expect(try await shared.value(for: 3, now: start.addingTimeInterval(62)) { 5 } == 5)
    }

    @Test func retryRepeatsUntilSuccess() async {
        struct Failure: Error {}
        var attempts = 0
        let value = await RadarRetry.untilSuccess(delay: .milliseconds(1)) {
            attempts += 1
            if attempts < 3 { throw Failure() }
            return attempts
        }
        #expect(value == 3)
    }

    @Test func retryStopsWhenCancelled() async {
        struct Failure: Error {}
        let task = Task { @MainActor in
            await RadarRetry.untilSuccess(delay: .milliseconds(1)) { () throws -> Int in throw Failure() }
        }
        task.cancel()
        #expect(await task.value == nil)
    }
}
