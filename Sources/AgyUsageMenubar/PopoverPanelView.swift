import AppKit
import SwiftUI

enum PopoverMetrics {
    static let cardWidth: CGFloat = 392
    static let cornerRadius: CGFloat = 14
    static let horizontalShadowPad: CGFloat = 16
    static let bottomShadowPad: CGFloat = 20
    static let topGap: CGFloat = 5

    static var panelWidth: CGFloat {
        cardWidth + horizontalShadowPad * 2
    }
}

struct PopoverShellView: View {
    @Bindable var viewModel: UsageViewModel

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: PopoverMetrics.cornerRadius, style: .continuous)

        PopoverContentView(viewModel: viewModel)
            .frame(width: PopoverMetrics.cardWidth)
            .background(
                VisualEffectBackground(cornerRadius: PopoverMetrics.cornerRadius)
            )
            .overlay(
                shape
                    .strokeBorder(Color.primary.opacity(0.16), lineWidth: 0.75)
            )
            .clipShape(shape)
            .shadow(color: Color.black.opacity(0.32), radius: 14, x: 0, y: 8)
            .padding(.horizontal, PopoverMetrics.horizontalShadowPad)
            .padding(.top, PopoverMetrics.topGap)
            .padding(.bottom, PopoverMetrics.bottomShadowPad)
            .fixedSize(horizontal: false, vertical: true)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            viewModel.onPopoverHeightMeasured?(proxy.size.height)
                        }
                        .onChange(of: proxy.size.height) { _, newHeight in
                            viewModel.onPopoverHeightMeasured?(newHeight)
                        }
                }
            )
    }
}

private struct VisualEffectBackground: NSViewRepresentable {
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = .popover
        nsView.state = .active
        nsView.layer?.cornerRadius = cornerRadius
    }
}
