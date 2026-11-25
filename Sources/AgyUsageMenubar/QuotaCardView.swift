import AgyUsageCore
import Charts
import SwiftUI

struct QuotaCardView: View {
    let projection: WindowProjection

    private var accent: Color {
        Theme.color(for: projection.status)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(accent)
                    Text(projection.kind.title)
                        .font(.system(size: 13, weight: .semibold))
                }

                Spacer()

                Text(UsageFormatters.verdict(for: projection))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(accent)

                Text("\(projection.roundedRemainingPercent)%")
                    .font(.system(size: 15, weight: .bold).monospacedDigit())
                    .frame(minWidth: 40, alignment: .trailing)
            }

            PaceBar(
                remainingFraction: projection.reading.remainingFraction,
                expectedFraction: projection.expectedRemainingFraction,
                accent: accent
            )

            QuotaChartView(projection: projection, accent: accent)
                .frame(height: 76)

            HStack {
                Text(UsageFormatters.axisStart(projection.cycleStart, kind: projection.kind))
                    .font(.system(size: 10.5).monospacedDigit())
                    .foregroundStyle(.secondary)

                Spacer()

                Text("Resets in \(UsageFormatters.duration(projection.timeUntilReset)) · \(UsageFormatters.resetTimestamp(projection.resetTime, kind: projection.kind))")
                    .font(.system(size: 10.5).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct PaceBar: View {
    let remainingFraction: Double
    let expectedFraction: Double
    let accent: Color

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let fillWidth = max(min(width * remainingFraction, width), 0)
            let paceX = max(min(width * expectedFraction, width - 1), 1)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.10))
                    .frame(height: 5)

                Capsule()
                    .fill(accent)
                    .frame(width: fillWidth, height: 5)

                RoundedRectangle(cornerRadius: 0.75)
                    .fill(Color.primary.opacity(0.45))
                    .frame(width: 1.5, height: 9)
                    .offset(x: paceX - 0.75)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 10)
    }
}

private struct QuotaChartView: View {
    let projection: WindowProjection
    let accent: Color

    var body: some View {
        Chart {
            // Ideal linear pace line from 100% at cycle start to 0% at reset.
            LineMark(
                x: .value("Time", projection.cycleStart),
                y: .value("Remaining", 100.0),
                series: .value("Series", "pace")
            )
            .foregroundStyle(Color.secondary.opacity(0.4))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))

            LineMark(
                x: .value("Time", projection.resetTime),
                y: .value("Remaining", 0.0),
                series: .value("Series", "pace")
            )
            .foregroundStyle(Color.secondary.opacity(0.4))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))

            // Recorded remaining curve.
            ForEach(projection.historyPoints) { point in
                AreaMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Remaining", point.remainingPercent)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [accent.opacity(0.22), accent.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Remaining", point.remainingPercent),
                    series: .value("Series", "actual")
                )
                .foregroundStyle(accent)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }

            // Projected burn trajectory from now to depletion or reset.
            ForEach(projection.projectionPoints) { point in
                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Remaining", point.remainingPercent),
                    series: .value("Series", "projection")
                )
                .foregroundStyle(accent.opacity(0.75))
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            }

            RuleMark(x: .value("Now", projection.now))
                .foregroundStyle(Color.primary.opacity(0.2))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))

            if let depletion = projection.projectedDepletionTime,
               depletion < projection.resetTime {
                PointMark(
                    x: .value("Depletion", max(depletion, projection.now)),
                    y: .value("Zero", 0.0)
                )
                .symbolSize(26)
                .foregroundStyle(accent)
            }
        }
        .chartXScale(domain: projection.cycleStart...projection.resetTime)
        .chartYScale(domain: 0...100)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(values: [0, 50, 100]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.primary.opacity(0.08))
                AxisValueLabel {
                    if let pct = value.as(Int.self) {
                        Text("\(pct)")
                            .font(.system(size: 9).monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .chartLegend(.hidden)
    }
}
