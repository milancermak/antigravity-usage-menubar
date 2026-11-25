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

                Text("\(projection.roundedRemainingPercent)%")
                    .font(.system(size: 15, weight: .bold).monospacedDigit())
            }

            PaceBar(
                remainingFraction: projection.reading.remainingFraction,
                expectedFraction: projection.expectedRemainingFraction,
                accent: accent
            )

            QuotaChartView(projection: projection, accent: accent)
                .frame(height: 82)

            HStack(spacing: 6) {
                Text(UsageFormatters.axisStart(projection.cycleStart, kind: projection.kind))
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.secondary)

                Spacer(minLength: 4)

                Text(footerSummary)
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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

    private var footerSummary: String {
        let reset = "Resets in \(UsageFormatters.duration(projection.timeUntilReset)) · \(UsageFormatters.resetTimestamp(projection.resetTime, kind: projection.kind))"
        let estimate = UsageFormatters.resetEstimate(for: projection)
        return "\(reset) · \(estimate)"
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

    @State private var hoveredDate: Date?

    var body: some View {
        let hoverSample: (date: Date, remainingPercent: Double, isProjected: Bool)? = hoveredDate.map { date in
            let s = projection.sample(at: date)
            return (date, s.remainingPercent, s.isProjected)
        }

        Chart {
            LineMark(
                x: .value("Time", projection.cycleStart),
                y: .value("Remaining", 100.0),
                series: .value("Series", "pace")
            )
            .foregroundStyle(Color.secondary.opacity(0.35))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))

            LineMark(
                x: .value("Time", projection.resetTime),
                y: .value("Remaining", 0.0),
                series: .value("Series", "pace")
            )
            .foregroundStyle(Color.secondary.opacity(0.35))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))

            ForEach(projection.historyPoints) { point in
                AreaMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Remaining", point.remainingPercent)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [accent.opacity(0.20), accent.opacity(0.02)],
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
                .foregroundStyle(Color.primary.opacity(0.18))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))

            if let depletion = projection.projectedDepletionTime,
               depletion < projection.resetTime {
                PointMark(
                    x: .value("Depletion", max(depletion, projection.now)),
                    y: .value("Zero", 0.0)
                )
                .symbolSize(24)
                .foregroundStyle(accent)
            }

            if let hoverSample {
                RuleMark(x: .value("Hover", hoverSample.date))
                    .foregroundStyle(Color.primary.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1))

                PointMark(
                    x: .value("HoverTime", hoverSample.date),
                    y: .value("HoverPct", hoverSample.remainingPercent)
                )
                .symbolSize(34)
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
        .chartOverlay { proxy in
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    Color.clear
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                guard let plotFrame = proxy.plotFrame else {
                                    hoveredDate = nil
                                    return
                                }
                                let frame = geo[plotFrame]
                                let plotX = location.x - frame.origin.x
                                guard plotX >= 0, plotX <= frame.width,
                                      let date = proxy.value(atX: plotX, as: Date.self) else {
                                    hoveredDate = nil
                                    return
                                }
                                hoveredDate = min(max(date, projection.cycleStart), projection.resetTime)
                            case .ended:
                                hoveredDate = nil
                            }
                        }

                    if let hoverSample,
                       let plotFrame = proxy.plotFrame,
                       let anchorX = proxy.position(forX: hoverSample.date) {
                        let frame = geo[plotFrame]
                        let pillWidth: CGFloat = projection.kind == .weekly ? 116 : 86
                        let rawX = frame.origin.x + anchorX - pillWidth / 2
                        let clampedX = min(max(rawX, frame.origin.x), frame.maxX - pillWidth)
                        let pctText = "\(hoverSample.isProjected ? "~" : "")\(Int(hoverSample.remainingPercent.rounded()))%"
                        let timeText = UsageFormatters.resetTimestamp(hoverSample.date, kind: projection.kind)

                        Text("\(timeText) · \(pctText)")
                            .font(.system(size: 10, weight: .medium).monospacedDigit())
                            .foregroundStyle(.primary)
                            .frame(width: pillWidth, height: 19)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(.regularMaterial)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .strokeBorder(accent.opacity(0.45), lineWidth: 0.75)
                            )
                            .offset(x: clampedX, y: 2)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
    }
}
