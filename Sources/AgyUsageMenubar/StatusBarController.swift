import AgyUsageCore
import AppKit
import SwiftUI

@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
    private struct StatusSignature: Equatable {
        let display: MenuBarDisplay
        let showPercent: Bool
        let fiveStatus: HealthStatus
        let fivePct: Int?
        let weekStatus: HealthStatus
        let weekPct: Int?
    }

    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let viewModel: UsageViewModel
    private var lastSignature: StatusSignature?
    private var lastButtonWindowFrame: NSRect = .zero
    private var isReanchoring = false
    private var windowObservers: [NSObjectProtocol] = []

    init(viewModel: UsageViewModel) {
        self.viewModel = viewModel
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()

        super.init()

        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self

        let hosting = NSHostingController(rootView: PopoverContentView(viewModel: viewModel))
        hosting.sizingOptions = .preferredContentSize
        popover.contentViewController = hosting

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(handleStatusItemClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
        }

        viewModel.onStatusBarNeedsUpdate = { [weak self] in
            self?.updateStatusItem()
        }

        updateStatusItem()
        observeStatusButtonWindow()
    }

    func updateStatusItem() {
        guard let button = statusItem.button else { return }

        let settings = viewModel.settings
        let signature = StatusSignature(
            display: settings.menuBarDisplay,
            showPercent: settings.showPercentageLabel,
            fiveStatus: viewModel.fiveHourProjection?.status ?? .unknown,
            fivePct: viewModel.fiveHourProjection?.roundedRemainingPercent,
            weekStatus: viewModel.weeklyProjection?.status ?? .unknown,
            weekPct: viewModel.weeklyProjection?.roundedRemainingPercent
        )

        button.toolTip = buildTooltip()
        guard signature != lastSignature else { return }
        lastSignature = signature

        let items: [(WindowProjection?, QuotaWindowKind)] = settings.menuBarDisplay.windows.map { kind in
            let proj = kind == .fiveHour ? viewModel.fiveHourProjection : viewModel.weeklyProjection
            return (proj, kind)
        }

        let attributed = NSMutableAttributedString()
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .medium)

        for (index, entry) in items.enumerated() {
            if index > 0 {
                let gap = settings.showPercentageLabel ? "  " : " "
                attributed.append(NSAttributedString(string: gap, attributes: [.font: font]))
            }

            let status = entry.0?.status ?? .unknown
            if let flame = makeFlameAttachment(status: status) {
                attributed.append(NSAttributedString(attachment: flame))
            }

            if settings.showPercentageLabel {
                let label: String
                if let proj = entry.0 {
                    label = " \(proj.roundedRemainingPercent)%"
                } else {
                    label = " --"
                }
                attributed.append(NSAttributedString(
                    string: label,
                    attributes: [
                        .font: font,
                        .foregroundColor: NSColor.labelColor
                    ]
                ))
            }
        }

        button.attributedTitle = attributed
        button.image = nil

        if windowObservers.isEmpty {
            observeStatusButtonWindow()
        }

        if popover.isShown {
            scheduleReanchorCheck()
        }
    }

    func popoverDidClose(_ notification: Notification) {
        if !isReanchoring {
            viewModel.showingSettings = false
        }
    }

    private func observeStatusButtonWindow() {
        guard let window = statusItem.button?.window else { return }
        lastButtonWindowFrame = window.frame

        let center = NotificationCenter.default
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            let obs = center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleStatusWindowGeometryChange()
                }
            }
            windowObservers.append(obs)
        }
    }

    private func handleStatusWindowGeometryChange() {
        guard let window = statusItem.button?.window else { return }
        let frame = window.frame
        guard frame != lastButtonWindowFrame else { return }
        lastButtonWindowFrame = frame

        if popover.isShown {
            reanchorPopoverNow()
        }
    }

    private func scheduleReanchorCheck() {
        // Fallback if AppKit adjusts the status bar frame slightly after attributedTitle updates.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
            self?.handleStatusWindowGeometryChange()
        }
    }

    private func reanchorPopoverNow() {
        guard popover.isShown, let button = statusItem.button, !isReanchoring else { return }
        button.window?.layoutIfNeeded()
        isReanchoring = true
        popover.close()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKeyAndOrderFront(nil)
        isReanchoring = false
    }

    private func makeFlameAttachment(status: HealthStatus) -> NSTextAttachment? {
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 13.5, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [Theme.nsColor(for: status)]))

        guard let symbol = NSImage(systemSymbolName: "flame.fill", accessibilityDescription: "Quota status")?
            .withSymbolConfiguration(symbolConfig) else {
            return nil
        }

        let targetSize = symbol.size
        let colored = NSImage(size: targetSize, flipped: false) { rect in
            symbol.draw(in: rect)
            return true
        }
        colored.isTemplate = false

        let attachment = NSTextAttachment()
        attachment.image = colored
        attachment.bounds = CGRect(x: 0, y: -2.4, width: targetSize.width, height: targetSize.height)
        return attachment
    }

    private func buildTooltip() -> String {
        var lines: [String] = ["Gemini Quota"]
        if let five = viewModel.fiveHourProjection {
            lines.append("5h: \(five.roundedRemainingPercent)% · \(UsageFormatters.resetEstimate(for: five)) (resets in \(UsageFormatters.duration(five.timeUntilReset)))")
        }
        if let week = viewModel.weeklyProjection {
            lines.append("7d: \(week.roundedRemainingPercent)% · \(UsageFormatters.resetEstimate(for: week)) (resets in \(UsageFormatters.duration(week.timeUntilReset)))")
        }
        if let error = viewModel.errorMessage {
            lines.append("Error: \(error)")
        }
        return lines.joined(separator: "\n")
    }

    @objc private func handleStatusItemClick(_ sender: AnyObject?) {
        guard let event = NSApp.currentEvent else {
            togglePopover()
            return
        }

        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.close()
        } else {
            viewModel.showingSettings = false
            NSApp.activate(ignoringOtherApps: true)
            if windowObservers.isEmpty {
                observeStatusButtonWindow()
            }
            if let window = button.window {
                lastButtonWindowFrame = window.frame
            }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKeyAndOrderFront(nil)
            DispatchQueue.main.async { [weak self] in
                self?.viewModel.refreshCountdowns()
            }
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        let refreshItem = NSMenuItem(title: "Refresh Now", action: #selector(triggerRefresh), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit", action: #selector(triggerQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func triggerRefresh() {
        Task { await viewModel.refreshNow() }
    }

    @objc private func triggerQuit() {
        NSApp.terminate(nil)
    }
}
