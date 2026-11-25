import AppKit
import SwiftUI

enum PopoverMetrics {
    static let cardWidth: CGFloat = 392
    static let arrowWidth: CGFloat = 22
    static let arrowHeight: CGFloat = 10
    static let cornerRadius: CGFloat = 12
    static let horizontalShadowPad: CGFloat = 16
    static let bottomShadowPad: CGFloat = 20
    static let topGap: CGFloat = 0
    static let minArrowInset: CGFloat = 26

    static var panelWidth: CGFloat {
        cardWidth + horizontalShadowPad * 2
    }
}

struct PopoverShellView: View {
    @Bindable var viewModel: UsageViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = PopoverShape(
            arrowCenterX: viewModel.popoverArrowX,
            arrowWidth: PopoverMetrics.arrowWidth,
            arrowHeight: PopoverMetrics.arrowHeight,
            cornerRadius: PopoverMetrics.cornerRadius
        )

        PopoverContentView(viewModel: viewModel)
            .padding(.top, PopoverMetrics.arrowHeight)
            .frame(width: PopoverMetrics.cardWidth)
            .background(
                VisualEffectBackground(shape: shape)
            )
            .overlay(
                shape
                    .stroke(Color.primary.opacity(0.18), lineWidth: 1.0)
            )
            .clipShape(shape)
            .shadow(color: Color.black.opacity(0.30), radius: 12, x: 0, y: 6)
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
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: viewModel.popoverArrowX)
    }
}

struct PopoverShape: Shape {
    var arrowCenterX: CGFloat
    let arrowWidth: CGFloat
    let arrowHeight: CGFloat
    let cornerRadius: CGFloat

    var animatableData: CGFloat {
        get { arrowCenterX }
        set { arrowCenterX = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let r = cornerRadius
        let top = rect.minY + arrowHeight
        let bottom = rect.maxY
        let left = rect.minX
        let right = rect.maxX

        let halfArrow = arrowWidth / 2
        let clampedCenter = min(max(arrowCenterX, left + r + halfArrow + 2), right - r - halfArrow - 2)
        let arrowLeft = clampedCenter - halfArrow
        let arrowRight = clampedCenter + halfArrow
        let tipRadius: CGFloat = 2.0

        var p = Path()
        p.move(to: CGPoint(x: left + r, y: top))

        p.addLine(to: CGPoint(x: arrowLeft - 2, y: top))
        p.addQuadCurve(
            to: CGPoint(x: clampedCenter - tipRadius, y: rect.minY + tipRadius),
            control: CGPoint(x: arrowLeft + halfArrow * 0.45, y: top)
        )
        p.addQuadCurve(
            to: CGPoint(x: clampedCenter + tipRadius, y: rect.minY + tipRadius),
            control: CGPoint(x: clampedCenter, y: rect.minY)
        )
        p.addQuadCurve(
            to: CGPoint(x: arrowRight + 2, y: top),
            control: CGPoint(x: arrowRight - halfArrow * 0.45, y: top)
        )

        p.addLine(to: CGPoint(x: right - r, y: top))
        p.addArc(
            center: CGPoint(x: right - r, y: top + r),
            radius: r,
            startAngle: .degrees(-90),
            endAngle: .degrees(0),
            clockwise: false
        )

        p.addLine(to: CGPoint(x: right, y: bottom - r))
        p.addArc(
            center: CGPoint(x: right - r, y: bottom - r),
            radius: r,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )

        p.addLine(to: CGPoint(x: left + r, y: bottom))
        p.addArc(
            center: CGPoint(x: left + r, y: bottom - r),
            radius: r,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )

        p.addLine(to: CGPoint(x: left, y: top + r))
        p.addArc(
            center: CGPoint(x: left + r, y: top + r),
            radius: r,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )

        p.closeSubpath()
        return p
    }
}

private final class MaskedVisualEffectView: NSVisualEffectView {
    var shape: PopoverShape? {
        didSet { updateMask() }
    }

    override func layout() {
        super.layout()
        updateMask()
    }

    private func updateMask() {
        guard let shape, bounds.width > 1, bounds.height > 1 else { return }
        let size = bounds.size
        let image = NSImage(size: size, flipped: true) { rect in
            NSColor.black.setFill()
            let cgPath = shape.path(in: rect).cgPath
            if let ctx = NSGraphicsContext.current?.cgContext {
                ctx.addPath(cgPath)
                ctx.fillPath()
            }
            return true
        }
        maskImage = image
    }
}

private struct VisualEffectBackground: NSViewRepresentable {
    let shape: PopoverShape

    func makeNSView(context: Context) -> MaskedVisualEffectView {
        let view = MaskedVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        view.shape = shape
        return view
    }

    func updateNSView(_ nsView: MaskedVisualEffectView, context: Context) {
        nsView.material = .popover
        nsView.state = .active
        nsView.shape = shape
    }
}
