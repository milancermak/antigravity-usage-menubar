import AgyUsageCore
import SwiftUI

struct PopoverContentView: View {
    @Bindable var viewModel: UsageViewModel
    @State private var showingSettings = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 12) {
            header

            if showingSettings {
                settingsBody
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .topTrailing)))
            } else {
                overviewBody
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            }

            footer
        }
        .padding(14)
        .frame(width: 360)
        .animation(reduceMotion ? nil : .spring(duration: 0.22, bounce: 0.0), value: showingSettings)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(showingSettings ? "Settings" : "Gemini Quota")
                .font(.system(size: 14, weight: .semibold))

            Spacer()

            if !showingSettings {
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
                showingSettings.toggle()
            } label: {
                Image(systemName: showingSettings ? "xmark" : "gearshape")
                    .font(.system(size: 12.5, weight: .medium))
            }
            .buttonStyle(.borderless)
            .help(showingSettings ? "Done" : "Settings")
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
        VStack(alignment: .leading, spacing: 14) {
            settingsSection("Menu Bar") {
                Picker("Show", selection: $viewModel.settings.menuBarDisplay) {
                    ForEach(MenuBarDisplay.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("Show % remaining", isOn: $viewModel.settings.showPercentageLabel)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            settingsSection("Prediction") {
                Picker("Pace", selection: $viewModel.settings.paceMethod) {
                    ForEach(PaceMethod.allCases) { method in
                        Text(method.label).tag(method)
                    }
                }
                .pickerStyle(.segmented)

                HStack {
                    Text("Safe buffer")
                        .font(.system(size: 12))
                    Spacer()
                    Stepper(
                        "\(Int(viewModel.settings.greenHeadroomPercent))%",
                        value: $viewModel.settings.greenHeadroomPercent,
                        in: 5...40,
                        step: 5
                    )
                    .font(.system(size: 12).monospacedDigit())
                    .controlSize(.small)
                }

                HStack {
                    Text("Red below")
                        .font(.system(size: 12))
                    Spacer()
                    Stepper(
                        "\(Int(viewModel.settings.redRemainingPercent))%",
                        value: $viewModel.settings.redRemainingPercent,
                        in: 5...30,
                        step: 5
                    )
                    .font(.system(size: 12).monospacedDigit())
                    .controlSize(.small)
                }
            }

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
