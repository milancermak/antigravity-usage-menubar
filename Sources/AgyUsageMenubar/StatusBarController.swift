import AgyUsageCore
import AppKit
import SwiftUI

@MainActor
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let viewModel: UsageViewModel

    init(viewModel: UsageViewModel) {
        self.viewModel = viewModel
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()

        super.init()

        popover.behavior = .transient
        popover.animates = true
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
    }

    func updateStatusItem() {
        guard let button = statusItem.button else { return }

        let settings = viewModel.settings
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
        button.toolTip = buildTooltip()

        // Re-anchor open popover after macOS recalculates the status item width.
        if popover.isShown {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.popover.isShown, let btn = self.statusItem.button else { return }
                btn.window?.layoutIfNeeded()
                let previousAnimates = self.popover.animates
                self.popover.animates = false
                self.popover.positioningRect = btn.bounds
                self.popover.show(relativeTo: btn.bounds, of: btn, preferredEdge: .minY)
                self.popover.animates = previousAnimates
            }
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
            lines.append("5h: \(five.roundedRemainingPercent)% · \(UsageFormatters.verdict(for: five)) (resets in \(UsageFormatters.duration(five.timeUntilReset)))")
        }
        if let week = viewModel.weeklyProjection {
            lines.append("7d: \(week.roundedRemainingPercent)% · \(UsageFormatters.verdict(for: week)) (resets in \(UsageFormatters.duration(week.timeUntilReset)))")
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
            popover.performClose(nil)
        } else {
            viewModel.refreshCountdowns()
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
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
