import AgyUsageCore
import AppKit
import SwiftUI

private final class StatusPanel: NSPanel {
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}

@MainActor
final class StatusBarController: NSObject {
    private struct StatusSignature: Equatable {
        let display: MenuBarDisplay
        let showPercent: Bool
        let fiveStatus: HealthStatus
        let fivePct: Int?
        let weekStatus: HealthStatus
        let weekPct: Int?
    }

    private let statusItem: NSStatusItem
    private let panel: StatusPanel
    private let hostingController: NSHostingController<PopoverShellView>
    private let viewModel: UsageViewModel

    private var lastSignature: StatusSignature?
    private var lockedCardOriginX: CGFloat?
    private var lockedPanelTopY: CGFloat?
    private var windowObservers: [NSObjectProtocol] = []
    private var resignObserver: NSObjectProtocol?
    private var globalClickMonitor: Any?
    private var localKeyMonitor: Any?

    init(viewModel: UsageViewModel) {
        self.viewModel = viewModel
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let panel = StatusPanel(
            contentRect: NSRect(x: 0, y: 0, width: 424, height: 420),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        self.panel = panel

        let hosting = NSHostingController(rootView: PopoverShellView(viewModel: viewModel))
        hosting.sizingOptions = []
        self.hostingController = hosting
        panel.contentViewController = hosting

        super.init()

        viewModel.onPopoverHeightMeasured = { [weak self] measuredHeight in
            DispatchQueue.main.async { [weak self] in
                self?.applyPanelHeight(measuredHeight)
            }
        }

        panel.onEscape = { [weak self] in
            self?.closePanel()
        }

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(handleStatusItemClick(_:))
            button.sendAction(on: [.leftMouseDown, .rightMouseUp])
            button.imagePosition = .imageLeading
            if let cell = button.cell as? NSButtonCell {
                cell.highlightsBy = []
                cell.showsStateBy = []
            }
        }

        viewModel.onStatusBarNeedsUpdate = { [weak self] in
            self?.updateStatusItem()
        }

        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.isMouseInsideStatusItem() else { return }
                self.closePanel()
            }
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

        if panel.isVisible {
            syncArrowToStatusItem()
            DispatchQueue.main.async { [weak self] in
                self?.syncArrowToStatusItem()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.syncArrowToStatusItem()
            }
        }
    }

    private func observeStatusButtonWindow() {
        guard let window = statusItem.button?.window else { return }

        let center = NotificationCenter.default
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            let obs = center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.syncArrowToStatusItem()
                }
            }
            windowObservers.append(obs)
        }
    }

    private func syncArrowToStatusItem() {
        guard panel.isVisible,
              let cardOriginX = lockedCardOriginX,
              let statusWindow = statusItem.button?.window else {
            return
        }

        let targetX = statusWindow.frame.midX - cardOriginX
        let minX = PopoverMetrics.minArrowInset
        let maxX = PopoverMetrics.cardWidth - PopoverMetrics.minArrowInset
        let clamped = min(max(targetX, minX), maxX)
        if abs(viewModel.popoverArrowX - clamped) > 0.25 {
            viewModel.popoverArrowX = clamped
        }
    }

    private func openPanel() {
        guard let button = statusItem.button, let statusWindow = button.window else { return }

        viewModel.showingSettings = false

        if windowObservers.isEmpty {
            observeStatusButtonWindow()
        }

        let panelWidth = PopoverMetrics.panelWidth
        let measured = hostingController.sizeThatFits(
            in: CGSize(width: panelWidth, height: CGFloat.greatestFiniteMagnitude)
        )
        let panelHeight = ceil(max(measured.height, 200))

        let statusRect = statusWindow.frame
        let screenFrame = (statusWindow.screen ?? NSScreen.main)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let desiredCardOriginX = statusRect.midX - PopoverMetrics.cardWidth / 2
        let minCardX = screenFrame.minX + 8
        let maxCardX = screenFrame.maxX - PopoverMetrics.cardWidth - 8
        let cardOriginX = min(max(desiredCardOriginX, minCardX), maxCardX)

        let panelOriginX = cardOriginX - PopoverMetrics.horizontalShadowPad
        let panelTopY = statusRect.minY
        let panelOriginY = panelTopY - panelHeight

        lockedCardOriginX = cardOriginX
        lockedPanelTopY = panelTopY

        let arrowX = min(
            max(statusRect.midX - cardOriginX, PopoverMetrics.minArrowInset),
            PopoverMetrics.cardWidth - PopoverMetrics.minArrowInset
        )
        viewModel.popoverArrowX = arrowX

        let frame = NSRect(x: panelOriginX, y: panelOriginY, width: panelWidth, height: panelHeight)
        panel.setFrame(frame, display: true)
        hostingController.view.frame = NSRect(origin: .zero, size: frame.size)

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        installDismissMonitors()

        DispatchQueue.main.async { [weak self] in
            self?.viewModel.refreshCountdowns()
            self?.remeasureAndApplyPanelHeight()
        }
    }

    private func remeasureAndApplyPanelHeight() {
        guard panel.isVisible else { return }
        let measured = hostingController.sizeThatFits(
            in: CGSize(width: PopoverMetrics.panelWidth, height: CGFloat.greatestFiniteMagnitude)
        )
        applyPanelHeight(measured.height)
    }

    private func applyPanelHeight(_ rawHeight: CGFloat) {
        guard panel.isVisible,
              let cardOriginX = lockedCardOriginX,
              let panelTopY = lockedPanelTopY else {
            return
        }

        let panelWidth = PopoverMetrics.panelWidth
        let panelHeight = ceil(max(rawHeight, 200))
        let panelOriginX = cardOriginX - PopoverMetrics.horizontalShadowPad
        let panelOriginY = panelTopY - panelHeight

        let newFrame = NSRect(x: panelOriginX, y: panelOriginY, width: panelWidth, height: panelHeight)
        if abs(panel.frame.height - newFrame.height) > 0.5 || abs(panel.frame.origin.y - newFrame.origin.y) > 0.5 {
            panel.setFrame(newFrame, display: true)
            hostingController.view.frame = NSRect(origin: .zero, size: newFrame.size)
        }
    }

    private func closePanel() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        lockedCardOriginX = nil
        lockedPanelTopY = nil
        viewModel.showingSettings = false
        removeDismissMonitors()
    }

    private func isMouseInsideStatusItem() -> Bool {
        guard let statusWindow = statusItem.button?.window else { return false }
        return statusWindow.frame.insetBy(dx: -4, dy: -4).contains(NSEvent.mouseLocation)
    }

    private func installDismissMonitors() {
        removeDismissMonitors()

        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let mouse = NSEvent.mouseLocation
                if self.isMouseInsideStatusItem() || self.panel.frame.contains(mouse) {
                    return
                }
                self.closePanel()
            }
        }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape
                self?.closePanel()
                return nil
            }
            return event
        }
    }

    private func removeDismissMonitors() {
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
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
            togglePanel()
            return
        }

        if event.type == .rightMouseUp {
            closePanel()
            showContextMenu()
        } else {
            togglePanel()
        }
    }

    private func togglePanel() {
        if panel.isVisible {
            closePanel()
        } else {
            openPanel()
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
