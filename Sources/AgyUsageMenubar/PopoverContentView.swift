import AgyUsageCore
import SwiftUI

struct PopoverContentView: View {
    @Bindable var viewModel: UsageViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 12) {
            header

            if viewModel.showingSettings {
                settingsBody
            } else {
                overviewBody
            }

            footer
        }
        .padding(14)
        .frame(width: 392)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(viewModel.showingSettings ? "Settings" : "Gemini Quota")
                .font(.system(size: 14, weight: .semibold))

            Spacer()

            if !viewModel.showingSettings {
                Button {
                    Task { await viewModel.refreshNow() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                        .rotationEffect(.degrees(viewModel.isRefreshing ? 360 : 0))
                        .animation(
                            viewModel.isRefreshing && !reduceMotion
                                ? .linear(duration: 0.9).repeatForever(autoreverses: false)
                                : .default,
                            value: viewModel.isRefreshing
                        )
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.isRefreshing)
                .help("Refresh now")
            }

            Button {
                viewModel.showingSettings.toggle()
            } label: {
                Image(systemName: viewModel.showingSettings ? "xmark" : "gearshape")
                    .font(.system(size: 12.5, weight: .medium))
            }
            .buttonStyle(.borderless)
            .help(viewModel.showingSettings ? "Done" : "Settings")
        }
    }

    private var overviewBody: some View {
        VStack(spacing: 10) {
            if let error = viewModel.errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.color(for: .caution))
                        .font(.system(size: 12))
                    Text(error)
                        .font(.system(size: 11.5))
                        .lineLimit(2)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Theme.color(for: .caution).opacity(0.12))
                )
            }

            if let fiveHour = viewModel.fiveHourProjection {
                QuotaCardView(projection: fiveHour)
            }

            if let weekly = viewModel.weeklyProjection {
                QuotaCardView(projection: weekly)
            }

            if viewModel.fiveHourProjection == nil && viewModel.weeklyProjection == nil {
                VStack(spacing: 10) {
                    if viewModel.isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "flame")
                            .font(.system(size: 22))
                            .foregroundStyle(.secondary)
                    }
                    Text(viewModel.isRefreshing ? "Fetching from agy..." : "No Gemini quota data")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 44)
            }
        }
    }

    private var settingsBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            settingsSection("Icons") {
                HStack(spacing: 10) {
                    Text("Show")
                        .font(.system(size: 12))
                    SwiftUISegmentedControl(
                        options: MenuBarDisplay.allCases,
                        selection: $viewModel.settings.menuBarDisplay,
                        label: \.label
                    )
                }

                Toggle("Show % remaining", isOn: $viewModel.settings.showPercentageLabel)
                    .toggleStyle(.switch)
                    .controlSize(.small)

                Divider()
                    .opacity(0.4)

                HStack {
                    HStack(spacing: 5) {
                        Text("Safety margin")
                            .font(.system(size: 12))
                        InfoHoverBadge(marginPercent: Int(viewModel.settings.safetyMarginPercent))
                    }
                    Spacer()
                    Stepper(
                        "\(Int(viewModel.settings.safetyMarginPercent))%",
                        value: $viewModel.settings.safetyMarginPercent,
                        in: 5...40,
                        step: 5
                    )
                    .font(.system(size: 12).monospacedDigit())
                    .controlSize(.small)
                }
            }
            .zIndex(10)

            settingsSection("Refresh") {
                HStack {
                    Text("Interval")
                        .font(.system(size: 12))
                    Spacer()
                    Picker("", selection: $viewModel.settings.pollIntervalSeconds) {
                        ForEach(UsageSettings.pollIntervalChoices, id: \.self) { sec in
                            Text(UsageFormatters.pollIntervalLabel(sec)).tag(sec)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 82)
                    .controlSize(.small)
                }

                HStack {
                    Text("agy")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    TextField(viewModel.resolvedAgyPath(), text: $viewModel.settings.agyPathOverride)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                        .controlSize(.small)
                }

                Toggle("Launch at login", isOn: Binding(
                    get: { viewModel.launchAtLogin },
                    set: { viewModel.setLaunchAtLogin($0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            HStack {
                Text("\(viewModel.snapshotCount) snapshots")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear History") {
                    viewModel.clearHistory()
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            }
        }
    }

    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.045))
            )
        }
    }

    private var footer: some View {
        HStack {
            TimelineView(.periodic(from: .now, by: 15)) { context in
                Text(UsageFormatters.relativeUpdated(viewModel.lastUpdated, now: context.date))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Quit") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
        }
    }
}

private struct SwiftUISegmentedControl<Option: Identifiable & Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let label: (Option) -> String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                let isSelected = option == selection
                Button {
                    selection = option
                } label: {
                    Text(label(option))
                        .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(isSelected ? Color.primary.opacity(0.16) : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.07))
        )
    }
}

private struct InfoHoverBadge: View {
    let marginPercent: Int
    @State private var isHovered = false

    var body: some View {
        Image(systemName: "info.circle")
            .font(.system(size: 11.5))
            .foregroundStyle(isHovered ? .primary : .secondary)
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovered = hovering
            }
            .overlay(alignment: .bottomLeading) {
                if isHovered {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Projected quota left at reset:")
                            .font(.system(size: 11, weight: .semibold))
                        HStack(spacing: 5) {
                            Circle().fill(Theme.color(for: .good)).frame(width: 6, height: 6)
                            Text("≥ \(marginPercent)% left at reset")
                        }
                        HStack(spacing: 5) {
                            Circle().fill(Theme.color(for: .caution)).frame(width: 6, height: 6)
                            Text("0–\(marginPercent)% left at reset")
                        }
                        HStack(spacing: 5) {
                            Circle().fill(Theme.color(for: .critical)).frame(width: 6, height: 6)
                            Text("Hits 0% before reset")
                        }
                    }
                    .font(.system(size: 10.5))
                    .foregroundStyle(.primary)
                    .padding(9)
                    .frame(width: 215, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.regularMaterial)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.18), lineWidth: 0.75)
                    )
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
                    .offset(x: -76, y: -22)
                    .allowsHitTesting(false)
                }
            }
    }
}
