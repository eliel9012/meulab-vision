import Accessibility
import Foundation
import SwiftUI

/// Pure summary of a single numeric series, used for VoiceOver chart descriptions.
struct LineChartSummary: Equatable, Sendable {
    let count: Int
    let minimum: Double
    let maximum: Double
    let first: Double
    let last: Double

    init?(values: [Double]) {
        guard let first = values.first, let last = values.last,
              let minimum = values.min(), let maximum = values.max() else { return nil }
        self.count = values.count
        self.minimum = minimum
        self.maximum = maximum
        self.first = first
        self.last = last
    }

    /// Y range padded so a flat series still produces a non-empty axis range.
    var axisRange: ClosedRange<Double> {
        minimum == maximum ? (minimum - 1)...(maximum + 1) : minimum...maximum
    }

    func text(unit: String) -> String {
        "\(count) pontos, mínimo \(Self.format(minimum))\(unit), máximo \(Self.format(maximum))\(unit), último \(Self.format(last))\(unit)."
    }

    static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }
}

/// Audio-graph / VoiceOver descriptor for a categorical-x line chart.
struct LineChartDescriptor: AXChartDescriptorRepresentable {
    let title: String
    let xTitle: String
    let yTitle: String
    let unit: String
    let points: [(label: String, value: Double)]

    func makeChartDescriptor() -> AXChartDescriptor {
        let summary = LineChartSummary(values: points.map(\.value))
        let xAxis = AXCategoricalDataAxisDescriptor(title: xTitle, categoryOrder: points.map(\.label))
        let unit = self.unit
        let yAxis = AXNumericDataAxisDescriptor(title: yTitle,
                                                range: summary?.axisRange ?? 0...1,
                                                gridlinePositions: []) { "\(LineChartSummary.format($0))\(unit)" }
        let series = AXDataSeriesDescriptor(name: yTitle, isContinuous: true,
                                            dataPoints: points.map { AXDataPoint(x: $0.label, y: $0.value) })
        return AXChartDescriptor(title: title,
                                 summary: summary?.text(unit: unit) ?? "Sem dados.",
                                 xAxis: xAxis, yAxis: yAxis,
                                 additionalAxes: [], series: [series])
    }
}
