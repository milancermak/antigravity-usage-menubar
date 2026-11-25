import Foundation

public enum QuotaWindowKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case fiveHour = "5h"
    case weekly = "weekly"

    public var id: String { rawValue }

    public var bucketKey: String {
        switch self {
        case .fiveHour: return "gemini-5h"
        case .weekly: return "gemini-weekly"
        }
    }

    public var duration: TimeInterval {
        switch self {
        case .fiveHour: return 5 * 3600
        case .weekly: return 7 * 24 * 3600
        }
    }

    public var title: String {
        switch self {
        case .fiveHour: return "5 hours"
        case .weekly: return "7 days"
        }
    }

    public var shortLabel: String {
        switch self {
        case .fiveHour: return "5h"
        case .weekly: return "7d"
        }
    }

    public var recentLookback: TimeInterval {
        switch self {
        case .fiveHour: return 45 * 60
        case .weekly: return 24 * 3600
        }
    }

    public var minElapsedForProjection: TimeInterval {
        switch self {
        case .fiveHour: return 5 * 60
        case .weekly: return 3 * 3600
        }
    }
}

public struct BucketReading: Codable, Equatable, Sendable {
    public let remainingFraction: Double
    public let resetTime: Date

    public init(remainingFraction: Double, resetTime: Date) {
        self.remainingFraction = min(max(remainingFraction, 0.0), 1.0)
        self.resetTime = resetTime
    }

    public var remainingPercent: Double {
        remainingFraction * 100.0
    }

    public var roundedRemainingPercent: Int {
        Int(remainingPercent.rounded())
    }
}

public struct QuotaSnapshot: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let fiveHour: BucketReading?
    public let weekly: BucketReading?

    public init(timestamp: Date, fiveHour: BucketReading?, weekly: BucketReading?) {
        self.timestamp = timestamp
        self.fiveHour = fiveHour
        self.weekly = weekly
    }

    public func reading(for kind: QuotaWindowKind) -> BucketReading? {
        switch kind {
        case .fiveHour: return fiveHour
        case .weekly: return weekly
        }
    }
}

public enum HealthStatus: String, Codable, Equatable, Sendable {
    case good
    case caution
    case critical
    case unknown
}

public enum PaceMethod: String, Codable, CaseIterable, Sendable, Identifiable {
    case cycleAverage = "cycle"
    case recent = "recent"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .cycleAverage: return "Cycle avg"
        case .recent: return "Recent"
        }
    }
}

public enum MenuBarIconMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case single = "single"
    case both = "both"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .single: return "1 Fire"
        case .both: return "2 Fires"
        }
    }
}

public struct ChartPoint: Equatable, Sendable, Identifiable {
    public let timestamp: Date
    public let remainingPercent: Double

    public var id: Date { timestamp }

    public init(timestamp: Date, remainingPercent: Double) {
        self.timestamp = timestamp
        self.remainingPercent = remainingPercent
    }
}

public struct WindowProjection: Equatable, Sendable {
    public let kind: QuotaWindowKind
    public let reading: BucketReading
    public let now: Date
    public let cycleStart: Date
    public let resetTime: Date
    public let expectedRemainingFraction: Double
    public let burnRatePerSecond: Double
    public let projectedRemainingAtReset: Double
    public let projectedDepletionTime: Date?
    public let status: HealthStatus
    public let historyPoints: [ChartPoint]
    public let projectionPoints: [ChartPoint]

    public var remainingPercent: Double {
        reading.remainingPercent
    }

    public var roundedRemainingPercent: Int {
        reading.roundedRemainingPercent
    }

    public var timeUntilReset: TimeInterval {
        max(resetTime.timeIntervalSince(now), 0)
    }

    public var willLastPastReset: Bool {
        projectedDepletionTime == nil
    }

    public var earlyDepletionLeadTime: TimeInterval? {
        guard let depletion = projectedDepletionTime else { return nil }
        return max(resetTime.timeIntervalSince(depletion), 0)
    }
}
