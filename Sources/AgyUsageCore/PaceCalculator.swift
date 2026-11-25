import Foundation

public enum PaceCalculator {
    public static func project(
        kind: QuotaWindowKind,
        reading: BucketReading,
        cycleSnapshots: [QuotaSnapshot],
        settings: UsageSettings,
        now: Date = Date()
    ) -> WindowProjection {
        let resetTime = reading.resetTime
        let cycleStart = resetTime.addingTimeInterval(-kind.duration)
        let elapsed = max(now.timeIntervalSince(cycleStart), 0)
        let timeUntilReset = max(resetTime.timeIntervalSince(now), 0)
        let expectedRemaining = min(max(timeUntilReset / kind.duration, 0), 1)

        let burnRate = computeBurnRate(
            kind: kind,
            reading: reading,
            cycleSnapshots: cycleSnapshots,
            method: settings.paceMethod,
            elapsed: elapsed,
            now: now
        )

        let projectedAtReset: Double
        let depletionTime: Date?

        if burnRate <= 1e-10 || timeUntilReset <= 0 {
            projectedAtReset = reading.remainingFraction
            depletionTime = nil
        } else {
            projectedAtReset = reading.remainingFraction - burnRate * timeUntilReset
            if projectedAtReset < 0 {
                let secondsToEmpty = reading.remainingFraction / burnRate
                depletionTime = now.addingTimeInterval(secondsToEmpty)
            } else {
                depletionTime = nil
            }
        }

        let status = classifyStatus(
            kind: kind,
            remaining: reading.remainingFraction,
            projectedAtReset: projectedAtReset,
            elapsed: elapsed,
            settings: settings
        )

        let historyPoints = buildHistoryPoints(
            kind: kind,
            reading: reading,
            cycleStart: cycleStart,
            cycleSnapshots: cycleSnapshots,
            now: now
        )

        let projectionPoints = buildProjectionPoints(
            reading: reading,
            now: now,
            resetTime: resetTime,
            projectedAtReset: projectedAtReset,
            depletionTime: depletionTime
        )

        return WindowProjection(
            kind: kind,
            reading: reading,
            now: now,
            cycleStart: cycleStart,
            resetTime: resetTime,
            expectedRemainingFraction: expectedRemaining,
            burnRatePerSecond: burnRate,
            projectedRemainingAtReset: projectedAtReset,
            projectedDepletionTime: depletionTime,
            status: status,
            historyPoints: historyPoints,
            projectionPoints: projectionPoints
        )
    }

    private static func computeBurnRate(
        kind: QuotaWindowKind,
        reading: BucketReading,
        cycleSnapshots: [QuotaSnapshot],
        method: PaceMethod,
        elapsed: TimeInterval,
        now: Date
    ) -> Double {
        let cycleRate: Double = elapsed >= 60
            ? max(1.0 - reading.remainingFraction, 0) / elapsed
            : 0

        guard method == .recent else {
            return cycleRate
        }

        let lookbackCutoff = now.addingTimeInterval(-kind.recentLookback)
        let candidate = cycleSnapshots.first { snap in
            snap.timestamp >= lookbackCutoff && now.timeIntervalSince(snap.timestamp) >= 120
        }

        guard let anchor = candidate,
              let anchorReading = anchor.reading(for: kind) else {
            return cycleRate
        }

        let dt = now.timeIntervalSince(anchor.timestamp)
        guard dt >= 120 else { return cycleRate }

        let deltaUsed = max(anchorReading.remainingFraction - reading.remainingFraction, 0)
        return deltaUsed / dt
    }

    private static func classifyStatus(
        kind: QuotaWindowKind,
        remaining: Double,
        projectedAtReset: Double,
        elapsed: TimeInterval,
        settings: UsageSettings
    ) -> HealthStatus {
        let margin = min(max(settings.safetyMarginPercent / 100.0, 0.01), 0.5)
        let used = 1.0 - remaining
        let hasSignal = elapsed >= kind.minElapsedForProjection || used >= 0.05

        if remaining <= 0.005 {
            return .critical
        }

        if hasSignal && projectedAtReset < 0 {
            return .critical
        }

        if hasSignal && projectedAtReset < margin {
            return .caution
        }

        if !hasSignal && projectedAtReset < 0 {
            return .caution
        }

        return .good
    }

    private static func buildHistoryPoints(
        kind: QuotaWindowKind,
        reading: BucketReading,
        cycleStart: Date,
        cycleSnapshots: [QuotaSnapshot],
        now: Date
    ) -> [ChartPoint] {
        var points: [ChartPoint] = []

        let sorted = cycleSnapshots
            .compactMap { snap -> ChartPoint? in
                guard let r = snap.reading(for: kind) else { return nil }
                return ChartPoint(timestamp: snap.timestamp, remainingPercent: r.remainingPercent)
            }
            .sorted { $0.timestamp < $1.timestamp }

        if let first = sorted.first {
            if first.timestamp.timeIntervalSince(cycleStart) > 60 {
                points.append(ChartPoint(timestamp: cycleStart, remainingPercent: 100.0))
            }
            points.append(contentsOf: sorted)
        } else {
            if now.timeIntervalSince(cycleStart) > 60 {
                points.append(ChartPoint(timestamp: cycleStart, remainingPercent: 100.0))
            }
        }

        if let last = points.last {
            if now.timeIntervalSince(last.timestamp) > 15 {
                points.append(ChartPoint(timestamp: now, remainingPercent: reading.remainingPercent))
            }
        } else {
            points.append(ChartPoint(timestamp: now, remainingPercent: reading.remainingPercent))
        }

        return points
    }

    private static func buildProjectionPoints(
        reading: BucketReading,
        now: Date,
        resetTime: Date,
        projectedAtReset: Double,
        depletionTime: Date?
    ) -> [ChartPoint] {
        guard resetTime > now else { return [] }

        let start = ChartPoint(timestamp: now, remainingPercent: reading.remainingPercent)
        if let depletionTime, depletionTime < resetTime {
            let clamped = max(depletionTime, now)
            return [start, ChartPoint(timestamp: clamped, remainingPercent: 0.0)]
        }

        let endPct = min(max(projectedAtReset * 100.0, 0.0), 100.0)
        return [start, ChartPoint(timestamp: resetTime, remainingPercent: endPct)]
    }
}
