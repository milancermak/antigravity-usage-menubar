import Foundation
import Testing
@testable import AgyUsageCore

@Suite("AgyStatusLineParser")
struct AgyStatusLineParserTests {
    @Test("Parses Gemini 5h and weekly buckets and ignores 3p/PII")
    func parsesGeminiOnly() throws {
        let ndjson = """
        {"product":"antigravity","agent_state":"initializing","email":"user@example.com"}
        {"product":"antigravity","email":"user@example.com","quota":{"3p-5h":{"remaining_fraction":0.5,"reset_time":"2026-11-25T13:52:28Z","reset_in_seconds":17999},"3p-weekly":{"remaining_fraction":0.82,"reset_time":"2026-12-01T16:28:00Z","reset_in_seconds":545731},"gemini-5h":{"remaining_fraction":0.9887998,"reset_time":"2026-11-25T11:44:06Z","reset_in_seconds":10297},"gemini-weekly":{"remaining_fraction":0.94276065,"reset_time":"2026-12-01T13:52:24Z","reset_in_seconds":536395}}}
        """

        let now = Date(timeIntervalSince1970: 1_795_595_000)
        let snapshot = try #require(AgyStatusLineParser.parseLatest(fromNDJSON: ndjson, now: now))

        let five = try #require(snapshot.fiveHour)
        #expect(abs(five.remainingFraction - 0.9887998) < 1e-6)

        let week = try #require(snapshot.weekly)
        #expect(abs(week.remainingFraction - 0.94276065) < 1e-6)
    }

    @Test("Ignores payload with only third-party quota")
    func ignoresThirdPartyOnly() {
        let json = """
        {"quota":{"3p-5h":{"remaining_fraction":0.5,"reset_time":"2026-11-25T13:52:28Z"}}}
        """
        #expect(AgyStatusLineParser.parse(line: json) == nil)
    }

    @Test("Falls back to reset_in_seconds when reset_time omitted")
    func fallbackResetInSeconds() throws {
        let json = """
        {"quota":{"gemini-weekly":{"remaining_fraction":0.75,"reset_in_seconds":3600}}}
        """
        let now = Date(timeIntervalSince1970: 1_795_595_000)
        let snapshot = try #require(AgyStatusLineParser.parse(line: json, now: now))
        let week = try #require(snapshot.weekly)
        #expect(abs(week.resetTime.timeIntervalSince(now) - 3600) < 0.01)
    }
}

@Suite("SnapshotStore")
struct SnapshotStoreTests {
    private func tempStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("agy-usage-test-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("snapshots.json")
    }

    @Test("Compacts consecutive flat readings and prunes expired week on rollover")
    func compactsAndPrunes() {
        let url = tempStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = SnapshotStore(fileURL: url)
        let t0 = Date(timeIntervalSince1970: 1_795_000_000)
        let week1Reset = t0.addingTimeInterval(3 * 24 * 3600)
        let fiveReset = t0.addingTimeInterval(3 * 3600)

        for minute in 0..<5 {
            let snap = QuotaSnapshot(
                timestamp: t0.addingTimeInterval(Double(minute) * 60),
                fiveHour: BucketReading(remainingFraction: 0.80, resetTime: fiveReset),
                weekly: BucketReading(remainingFraction: 0.70, resetTime: week1Reset)
            )
            store.append(snap)
        }

        // Flat plateau keeps first and latest timestamps (2 points, not 5).
        #expect(store.count == 2)

        // Advance past week1Reset into week 2; expired week 1 snapshots must be deleted.
        let week2Now = week1Reset.addingTimeInterval(3600)
        let week2Reset = week2Now.addingTimeInterval(QuotaWindowKind.weekly.duration - 3600)
        let week2Snap = QuotaSnapshot(
            timestamp: week2Now,
            fiveHour: BucketReading(remainingFraction: 0.99, resetTime: week2Now.addingTimeInterval(4 * 3600)),
            weekly: BucketReading(remainingFraction: 0.99, resetTime: week2Reset)
        )
        store.append(week2Snap)

        #expect(store.count == 1)
        #expect(store.latestSnapshot == week2Snap)
    }
}

@Suite("PaceCalculator")
struct PaceCalculatorTests {
    @Test("Healthy headroom classifies as green")
    func healthyGreen() {
        let now = Date(timeIntervalSince1970: 1_795_595_000)
        let reset = now.addingTimeInterval(4 * 24 * 3600) // 3 days elapsed, 4 days left
        let reading = BucketReading(remainingFraction: 0.85, resetTime: reset)

        let proj = PaceCalculator.project(
            kind: .weekly,
            reading: reading,
            cycleSnapshots: [],
            settings: UsageSettings(),
            now: now
        )

        #expect(proj.status == .good)
        #expect(proj.willLastPastReset)
        #expect(proj.projectedRemainingAtReset > 0.60)
    }

    @Test("Tight margin at reset classifies as amber")
    func tightAmber() {
        let now = Date(timeIntervalSince1970: 1_795_595_000)
        // Halfway through 5h window (2.5h elapsed, 2.5h remaining), 54% remaining -> projected +8% at reset (< 15% default green headroom).
        let reset = now.addingTimeInterval(2.5 * 3600)
        let reading = BucketReading(remainingFraction: 0.54, resetTime: reset)

        let proj = PaceCalculator.project(
            kind: .fiveHour,
            reading: reading,
            cycleSnapshots: [],
            settings: UsageSettings(),
            now: now
        )

        #expect(proj.status == .caution)
        #expect(proj.willLastPastReset)
    }

    @Test("Projected depletion before reset classifies as red")
    func overPaceRed() throws {
        let now = Date(timeIntervalSince1970: 1_795_595_000)
        // 2h elapsed, 3h left, already burned 60% -> burns 30%/h -> runs dry in ~1.33h (before 3h reset).
        let reset = now.addingTimeInterval(3 * 3600)
        let reading = BucketReading(remainingFraction: 0.40, resetTime: reset)

        let proj = PaceCalculator.project(
            kind: .fiveHour,
            reading: reading,
            cycleSnapshots: [],
            settings: UsageSettings(),
            now: now
        )

        #expect(proj.status == .critical)
        #expect(!proj.willLastPastReset)
        let dryAt = try #require(proj.projectedDepletionTime)
        #expect(dryAt < reset)
    }

    @Test("Recent pace mode reacts to sudden heavy burn")
    func recentPaceDetectsSpike() {
        let now = Date(timeIntervalSince1970: 1_795_595_000)
        let reset = now.addingTimeInterval(5 * 24 * 3600) // 2 days elapsed, 5 days left

        // Overall 2-day burn looks fine (85% left), but burned 12% in the last 3 hours!
        let earlier = QuotaSnapshot(
            timestamp: now.addingTimeInterval(-3 * 3600),
            fiveHour: nil,
            weekly: BucketReading(remainingFraction: 0.97, resetTime: reset)
        )
        let current = BucketReading(remainingFraction: 0.85, resetTime: reset)

        var settings = UsageSettings()
        settings.paceMethod = .recent

        let proj = PaceCalculator.project(
            kind: .weekly,
            reading: current,
            cycleSnapshots: [earlier],
            settings: settings,
            now: now
        )

        #expect(proj.status == .critical)
        #expect(!proj.willLastPastReset)
    }

    @Test("Default settings use 1-minute poll interval and both windows")
    func defaultSettings() {
        let settings = UsageSettings()
        #expect(settings.pollIntervalSeconds == 60)
        #expect(settings.menuBarDisplay == .both)
        #expect(settings.showPercentageLabel == true)
    }

    @Test("Hover sampling interpolates history and projects future burn")
    func hoverSampling() {
        let now = Date(timeIntervalSince1970: 1_795_595_000)
        let reset = now.addingTimeInterval(2.5 * 3600) // 2.5h elapsed, 2.5h left
        let reading = BucketReading(remainingFraction: 0.60, resetTime: reset)

        let proj = PaceCalculator.project(
            kind: .fiveHour,
            reading: reading,
            cycleSnapshots: [],
            settings: UsageSettings(),
            now: now
        )

        // Midpoint of past elapsed time (1.25h ago) -> linearly interpolated halfway from 100% to 60% = 80%.
        let pastSample = proj.sample(at: now.addingTimeInterval(-1.25 * 3600))
        #expect(!pastSample.isProjected)
        #expect(abs(pastSample.remainingPercent - 80.0) < 0.5)

        // Future halfway to reset (1.25h ahead) -> burns 16%/h -> 60% - 20% = 40%.
        let futureSample = proj.sample(at: now.addingTimeInterval(1.25 * 3600))
        #expect(futureSample.isProjected)
        #expect(abs(futureSample.remainingPercent - 40.0) < 0.5)
    }
}
