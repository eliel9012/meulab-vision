import Accessibility
import Foundation
import Testing
@testable import MeuLabVision

@Suite("Fase 3B · logs Docker")
struct Fase3BDockerLogsTests {
    @Test func queryItemsUseDefaults() {
        let items = DockerLogsRequest.queryItems(container: "radar")
        #expect(items.map(\.name) == ["container", "tail", "since"])
        #expect(items.map(\.value) == ["radar", "200", "3600"])
    }

    @Test func queryItemsCustomValues() {
        let items = DockerLogsRequest.queryItems(container: "acars", tail: 50, since: 60)
        #expect(items.map(\.value) == ["acars", "50", "60"])
    }

    @Test func displayTextFallsBackOnBlank() {
        #expect(DockerLogsRequest.displayText("") == DockerLogsRequest.emptyMessage)
        #expect(DockerLogsRequest.displayText("  \n\t") == DockerLogsRequest.emptyMessage)
        #expect(DockerLogsRequest.displayText("line 1\n") == "line 1\n")
    }

    @Test func titleForContainer() {
        #expect(DockerLogsRequest.title(for: nil) == "Logs Docker")
        #expect(DockerLogsRequest.title(for: "") == "Logs Docker")
        #expect(DockerLogsRequest.title(for: "radar") == "Logs · radar")
    }
}

@Suite("Fase 3B · acessibilidade de gráficos")
struct Fase3BChartAccessibilityTests {
    @Test func summaryNilWhenEmpty() {
        #expect(LineChartSummary(values: []) == nil)
    }

    @Test func summaryMinMaxLast() throws {
        let summary = try #require(LineChartSummary(values: [12, 40.5, 3, 27]))
        #expect(summary.count == 4)
        #expect(summary.minimum == 3)
        #expect(summary.maximum == 40.5)
        #expect(summary.first == 12)
        #expect(summary.last == 27)
        #expect(summary.axisRange == 3...40.5)
    }

    @Test func flatSeriesGetsPaddedRange() throws {
        let summary = try #require(LineChartSummary(values: [5, 5, 5]))
        #expect(summary.axisRange == 4...6)
    }

    @Test func summaryTextMentionsValuesAndUnit() throws {
        let text = try #require(LineChartSummary(values: [10, 20])).text(unit: "%")
        #expect(text.hasPrefix("2 pontos"))
        #expect(text.contains("10%"))
        #expect(text.contains("20%"))
    }

    @Test func descriptorBuildsSingleSeries() {
        let descriptor = LineChartDescriptor(title: "CPU", xTitle: "Horário", yTitle: "Uso", unit: "%",
                                             points: [("10:00", 12), ("10:05", 30)])
        let chart = descriptor.makeChartDescriptor()
        #expect(chart.title == "CPU")
        #expect(chart.series.count == 1)
        #expect(chart.series.first?.dataPoints.count == 2)
    }

    @Test func descriptorEmptyStillValid() {
        let chart = LineChartDescriptor(title: "Vazio", xTitle: "x", yTitle: "y", unit: "", points: [])
            .makeChartDescriptor()
        #expect(chart.summary == "Sem dados.")
        #expect(chart.series.first?.dataPoints.isEmpty == true)
    }
}

@Suite("Fase 3B · profundidade e progresso")
struct Fase3BDepthAndPlaybackTests {
    @Test func depthIsClamped() {
        #expect(SpatialDepth.clamped(-5) == 0)
        #expect(SpatialDepth.clamped(SpatialDepth.card) == SpatialDepth.card)
        #expect(SpatialDepth.clamped(100) == 24)
    }

    @Test func clearsProgressNearStartOrEnd() {
        #expect(VisionPlaybackProgress.shouldClear(seconds: 10, duration: 1_800))
        #expect(VisionPlaybackProgress.shouldClear(seconds: 1_750, duration: 1_800))
        #expect(!VisionPlaybackProgress.shouldClear(seconds: 600, duration: 1_800))
        #expect(!VisionPlaybackProgress.shouldClear(seconds: 600, duration: 0))
    }
}
