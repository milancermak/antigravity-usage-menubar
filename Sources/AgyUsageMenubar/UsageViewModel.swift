import AgyUsageCore
import AppKit
import Foundation
import Observation
import ServiceManagement

@MainActor
@Observable
final class UsageViewModel {
    var settings: UsageSettings {
        didSet {
            guard settings != oldValue else { return }
            UsageSettingsStore.save(settings)
            recomputeProjections()
            if settings.pollIntervalSeconds != oldValue.pollIntervalSeconds {
                restartPollingLoop()
            }
            onStatusBarNeedsUpdate?()
        }
    }

    var fiveHourProjection: WindowProjection?
    var weeklyProjection: WindowProjection?
    var lastUpdated: Date?
    var isRefreshing: Bool = false
    var errorMessage: String?
    var snapshotCount: Int = 0
    var launchAtLogin: Bool = false
    var showingSettings: Bool = false
    var popoverArrowX: CGFloat = 196

    @ObservationIgnored var onStatusBarNeedsUpdate: (() -> Void)?
    @ObservationIgnored var onPopoverHeightMeasured: ((CGFloat) -> Void)?

    @ObservationIgnored private let store: SnapshotStore
    @ObservationIgnored private let fetcher: QuotaFetching
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var activeRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?

    init(
        store: SnapshotStore = SnapshotStore(),
        fetcher: QuotaFetching = AgyQuotaFetcher()
    ) {
        self.store = store
        self.fetcher = fetcher
        self.settings = UsageSettingsStore.load()
        self.launchAtLogin = SMAppService.mainApp.status == .enabled

        recomputeProjections()
        observeWake()
    }

    func start() {
        restartPollingLoop()
        Task { await refreshNow() }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        activeRefreshTask?.cancel()
        activeRefreshTask = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
    }

    func refreshNow() async {
        if let activeRefreshTask {
            await activeRefreshTask.value
            return
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            self.isRefreshing = true
            defer {
                self.isRefreshing = false
                self.activeRefreshTask = nil
                self.onStatusBarNeedsUpdate?()
            }

            do {
                let snapshot = try await self.fetcher.fetchQuota(agyPathOverride: self.settings.agyPathOverride)
                self.store.append(snapshot)
                self.lastUpdated = snapshot.timestamp
                self.errorMessage = nil
                self.recomputeProjections(now: snapshot.timestamp)
            } catch {
                self.errorMessage = error.localizedDescription
                self.recomputeProjections()
            }
        }

        activeRefreshTask = task
        await task.value
    }

    func clearHistory() {
        store.clear()
        fiveHourProjection = nil
        weeklyProjection = nil
        lastUpdated = nil
        snapshotCount = 0
        onStatusBarNeedsUpdate?()
        Task { await refreshNow() }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = SMAppService.mainApp.status == .enabled
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    func resolvedAgyPath() -> String {
        AgyQuotaFetcher.resolveBinaryPath(override: settings.agyPathOverride) ?? "Not found"
    }

    func refreshCountdowns() {
        recomputeProjections(now: Date())
    }

    private func recomputeProjections(now: Date = Date()) {
        store.prune(now: now)
        snapshotCount = store.count

        guard let latest = store.latestSnapshot else {
            fiveHourProjection = nil
            weeklyProjection = nil
            return
        }

        lastUpdated = latest.timestamp

        if let fiveReading = latest.fiveHour {
            let cycle = store.cycleSnapshots(for: .fiveHour, activeReading: fiveReading)
            fiveHourProjection = PaceCalculator.project(
                kind: .fiveHour,
                reading: fiveReading,
                cycleSnapshots: cycle,
                settings: settings,
                now: now
            )
        } else {
            fiveHourProjection = nil
        }

        if let weekReading = latest.weekly {
            let cycle = store.cycleSnapshots(for: .weekly, activeReading: weekReading)
            weeklyProjection = PaceCalculator.project(
                kind: .weekly,
                reading: weekReading,
                cycleSnapshots: cycle,
                settings: settings,
                now: now
            )
        } else {
            weeklyProjection = nil
        }
    }

    private func restartPollingLoop() {
        pollTask?.cancel()
        let interval = max(settings.pollIntervalSeconds, 15)
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled, let self else { break }
                await self.refreshNow()
            }
        }
    }

    private func observeWake() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(2))
                await self?.refreshNow()
            }
        }
    }
}
