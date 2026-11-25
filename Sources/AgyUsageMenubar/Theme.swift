import AgyUsageCore
import AppKit
import SwiftUI

enum Theme {
    static func nsColor(for status: HealthStatus) -> NSColor {
        switch status {
        case .good:
            // Muted sage green: calm in the menu bar without neon glare.
            return NSColor(srgbRed: 0.29, green: 0.65, blue: 0.44, alpha: 1.0)
        case .caution:
            // Warm muted amber.
            return NSColor(srgbRed: 0.84, green: 0.62, blue: 0.26, alpha: 1.0)
        case .critical:
            // Clear coral-red with controlled saturation.
            return NSColor(srgbRed: 0.83, green: 0.36, blue: 0.35, alpha: 1.0)
        case .unknown:
            return NSColor.secondaryLabelColor
        }
    }

    static func color(for status: HealthStatus) -> Color {
        Color(nsColor: nsColor(for: status))
    }
}

enum UsageFormatters {
    static func duration(_ interval: TimeInterval) -> String {
        let totalSeconds = max(Int(interval.rounded()), 0)
        let days = totalSeconds / 86_400
        let hours = (totalSeconds % 86_400) / 3_600
        let minutes = (totalSeconds % 3_600) / 60

        if days > 0 {
            return hours > 0 ? "\(days)d \(hours)h" : "\(days)d"
        }
        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
        return "\(max(minutes, 1))m"
    }

    static func resetTimestamp(_ date: Date, kind: QuotaWindowKind) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        switch kind {
        case .fiveHour:
            formatter.dateFormat = "HH:mm"
        case .weekly:
            formatter.dateFormat = "EEE HH:mm"
        }
        return formatter.string(from: date)
    }

    static func axisStart(_ date: Date, kind: QuotaWindowKind) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        switch kind {
        case .fiveHour:
            formatter.dateFormat = "HH:mm"
        case .weekly:
            formatter.dateFormat = "d MMM"
        }
        return formatter.string(from: date)
    }

    static func verdict(for projection: WindowProjection) -> String {
        if let depletion = projection.projectedDepletionTime {
            let untilDry = max(depletion.timeIntervalSince(projection.now), 0)
            switch projection.kind {
            case .fiveHour:
                return "Dry in \(duration(untilDry))"
            case .weekly:
                return "Dry \(resetTimestamp(depletion, kind: .weekly))"
            }
        }

        if projection.burnRatePerSecond <= 1e-10 {
            return "On track"
        }

        let leftAtReset = max(Int((projection.projectedRemainingAtReset * 100.0).rounded()), 0)
        return "~\(leftAtReset)% at reset"
    }

    static func relativeUpdated(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "Waiting for agy" }
        let seconds = max(Int(now.timeIntervalSince(date)), 0)
        if seconds < 15 { return "Updated just now" }
        if seconds < 60 { return "Updated \(seconds)s ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "Updated \(minutes)m ago" }
        return "Updated \(minutes / 60)h ago"
    }

    static func pollIntervalLabel(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        return "\(seconds / 60)m"
    }
}
