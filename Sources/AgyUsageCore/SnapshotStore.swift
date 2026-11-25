import Foundation

public final class SnapshotStore: @unchecked Sendable {
    public let fileURL: URL
    private let lock = NSLock()
    private var snapshots: [QuotaSnapshot] = []

    public init(fileURL: URL = SnapshotStore.defaultFileURL()) {
        self.fileURL = fileURL
        self.snapshots = Self.readFromDisk(url: fileURL)
        pruneLocked(now: Date())
    }

    public static func defaultFileURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return appSupport
            .appendingPathComponent("AgyUsageMenubar", isDirectory: true)
            .appendingPathComponent("snapshots.json")
    }

    public var allSnapshots: [QuotaSnapshot] {
        lock.withLock { snapshots }
    }

    public var latestSnapshot: QuotaSnapshot? {
        lock.withLock { snapshots.last }
    }

    public var count: Int {
        lock.withLock { snapshots.count }
    }

    @discardableResult
    public func append(_ snapshot: QuotaSnapshot, now: Date? = nil) -> [QuotaSnapshot] {
        let referenceNow = now ?? snapshot.timestamp
        return lock.withLock {
            if snapshots.count >= 2,
               let prev = snapshots.last,
               isEquivalent(snapshots[snapshots.count - 2], prev),
               isEquivalent(prev, snapshot) {
                snapshots[snapshots.count - 1] = snapshot
            } else if let prev = snapshots.last,
                      abs(snapshot.timestamp.timeIntervalSince(prev.timestamp)) < 2,
                      isEquivalent(prev, snapshot) {
                snapshots[snapshots.count - 1] = snapshot
            } else {
                snapshots.append(snapshot)
            }

            pruneLocked(now: referenceNow)
            writeToDiskLocked()
            return snapshots
        }
    }

    @discardableResult
    public func prune(now: Date = Date()) -> [QuotaSnapshot] {
        lock.withLock {
            let before = snapshots.count
            pruneLocked(now: now)
            if snapshots.count != before {
                writeToDiskLocked()
            }
            return snapshots
        }
    }

    public func clear() {
        lock.withLock {
            snapshots.removeAll()
            writeToDiskLocked()
        }
    }

    public func cycleSnapshots(for kind: QuotaWindowKind, activeReading: BucketReading) -> [QuotaSnapshot] {
        let cycleStart = activeReading.resetTime.addingTimeInterval(-kind.duration)
        let tolerance: TimeInterval = 180

        return lock.withLock {
            snapshots.filter { snap in
                guard let reading = snap.reading(for: kind) else { return false }
                let matchesReset = abs(reading.resetTime.timeIntervalSince(activeReading.resetTime)) <= tolerance
                let inWindow = snap.timestamp >= cycleStart.addingTimeInterval(-60)
                return matchesReset && inWindow
            }
        }
    }

    private func pruneLocked(now: Date) {
        let maxAgeCutoff = now.addingTimeInterval(-QuotaWindowKind.weekly.duration)

        var cutoff = maxAgeCutoff
        if let latestWeekly = snapshots.reversed().compactMap(\.weekly).first,
           latestWeekly.resetTime > now {
            let activeWeekStart = latestWeekly.resetTime.addingTimeInterval(-QuotaWindowKind.weekly.duration)
            cutoff = max(cutoff, activeWeekStart.addingTimeInterval(-60))
        }

        snapshots.removeAll { $0.timestamp < cutoff }
    }

    private func isEquivalent(_ a: QuotaSnapshot, _ b: QuotaSnapshot) -> Bool {
        bucketEquivalent(a.fiveHour, b.fiveHour) && bucketEquivalent(a.weekly, b.weekly)
    }

    private func bucketEquivalent(_ a: BucketReading?, _ b: BucketReading?) -> Bool {
        switch (a, b) {
        case (nil, nil):
            return true
        case let (lhs?, rhs?):
            let sameFrac = abs(lhs.remainingFraction - rhs.remainingFraction) < 0.00005
            let sameReset = abs(lhs.resetTime.timeIntervalSince(rhs.resetTime)) < 90
            return sameFrac && sameReset
        default:
            return false
        }
    }

    private func writeToDiskLocked() {
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshots) else { return }

        try? data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    private static func readFromDisk(url: URL) -> [QuotaSnapshot] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([QuotaSnapshot].self, from: data)) ?? []
    }
}
