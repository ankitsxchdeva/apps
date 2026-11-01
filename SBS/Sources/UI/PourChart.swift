import Charts
import SwiftUI
import DesignSystem

/// Every scale on one time axis. Weight and flow are never mixed on one
/// chart — they get one chart each.
struct PourChart: View {
    enum Metric {
        case weight, flow

        var title: String { self == .weight ? "Weight" : "Flow" }
        var unit: String { self == .weight ? "g" : "g/s" }

        func value(_ sample: Sample) -> Double {
            self == .weight ? sample.grams : sample.flow
        }
    }

    let run: Run
    var metric: Metric = .weight

    var body: some View {
        Chart {
            ForEach(run.slots) { slot in
                ForEach(Array(run.samples(slot).enumerated()), id: \.offset) { _, sample in
                    LineMark(
                        x: .value("Time", sample.t),
                        y: .value(metric.title, metric.value(sample)),
                        series: .value("Scale", run.seriesName(slot))
                    )
                    .foregroundStyle(by: .value("Scale", run.seriesName(slot)))
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
                }
                if let last = run.samples(slot).last {
                    // Direct label at the end of each line, so identity is
                    // never color alone.
                    PointMark(x: .value("Time", last.t), y: .value(metric.title, metric.value(last)))
                        .foregroundStyle(slot.color)
                        .symbolSize(50)
                        .annotation(position: .trailing, spacing: 4) {
                            Text(slot.name)
                                .font(.dsCaption)
                                .foregroundStyle(Color.dsInkSecondary)
                        }
                }
            }
        }
        .chartForegroundStyleScale(domain: run.slots.map(run.seriesName), range: run.slots.map(\.color))
        .chartLegend(position: .top, alignment: .leading)
        .chartXAxisLabel("seconds", alignment: .trailing)
        .chartYAxisLabel(metric.unit)
        .chartXAxis {
            AxisMarks { _ in
                AxisGridLine().foregroundStyle(Color.dsSeparator)
                AxisValueLabel().foregroundStyle(Color.dsInkSecondary)
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisGridLine().foregroundStyle(Color.dsSeparator)
                AxisValueLabel().foregroundStyle(Color.dsInkSecondary)
            }
        }
        .accessibilityLabel("\(metric.title) over time, scales \(run.slots.map(run.seriesName).formatted(.list(type: .and)))")
    }
}
