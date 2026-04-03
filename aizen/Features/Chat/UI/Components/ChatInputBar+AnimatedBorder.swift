import AppKit
import SwiftUI

struct AnimatedGradientBorder: NSViewRepresentable {
    let cornerRadius: CGFloat
    let colors: [Color]
    let dashed: Bool
    let reduceMotion: Bool
    let isActive: Bool
    private let lineWidth: CGFloat = 2
    private let cycleSeconds: TimeInterval = 10

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> GradientBorderView {
        let view = GradientBorderView()
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: GradientBorderView, context: Context) {
        context.coordinator.update(
            in: nsView,
            cornerRadius: cornerRadius,
            colors: colors,
            dashed: dashed,
            reduceMotion: reduceMotion,
            isActive: isActive,
            lineWidth: lineWidth,
            cycleSeconds: cycleSeconds
        )
    }

    final class Coordinator {
        private let containerLayer = CALayer()
        private let gradientLayer = CAGradientLayer()
        private let maskLayer = CAShapeLayer()
        private var isAnimating = false
        private var currentCornerRadius: CGFloat = 0
        private var currentLineWidth: CGFloat = 0
        private weak var hostView: GradientBorderView?
        private let pulseKey = "aizen.gradientBorder.pulse"

        func attach(to view: GradientBorderView) {
            guard hostView == nil else { return }
            hostView = view
            view.wantsLayer = true
            view.layer = CALayer()
            view.layer?.masksToBounds = false
            view.layer?.addSublayer(containerLayer)
            containerLayer.masksToBounds = false
            containerLayer.addSublayer(gradientLayer)
            containerLayer.mask = maskLayer
            gradientLayer.type = .conic
            gradientLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
            gradientLayer.endPoint = CGPoint(x: 1, y: 1)
            maskLayer.fillColor = nil
            maskLayer.strokeColor = NSColor.white.cgColor
            maskLayer.lineCap = .round
            view.layoutHandler = { [weak self] bounds in
                self?.layout(in: bounds)
            }
        }

        func update(
            in view: GradientBorderView,
            cornerRadius: CGFloat,
            colors: [Color],
            dashed: Bool,
            reduceMotion: Bool,
            isActive: Bool,
            lineWidth: CGFloat,
            cycleSeconds: TimeInterval
        ) {
            if hostView == nil {
                attach(to: view)
            }

            currentCornerRadius = cornerRadius
            currentLineWidth = lineWidth

            let nsColors = colors.map { NSColor($0).cgColor }
            gradientLayer.colors = nsColors + [nsColors.first].compactMap { $0 }
            maskLayer.lineWidth = lineWidth
            maskLayer.lineDashPattern = dashed ? [6, 6] : nil

            if let scale = view.window?.backingScaleFactor {
                view.layer?.contentsScale = scale
                containerLayer.contentsScale = scale
                gradientLayer.contentsScale = scale
                maskLayer.contentsScale = scale
            }

            layout(in: view.bounds)
            updateAnimation(reduceMotion: reduceMotion, isActive: isActive, cycleSeconds: cycleSeconds)
        }

        private func layout(in bounds: CGRect) {
            guard !bounds.isEmpty else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            containerLayer.frame = bounds
            gradientLayer.frame = bounds
            maskLayer.frame = bounds
            let inset = max(currentLineWidth / 2, 0.5)
            let rect = bounds.insetBy(dx: inset, dy: inset)
            maskLayer.path = CGPath(
                roundedRect: rect,
                cornerWidth: currentCornerRadius,
                cornerHeight: currentCornerRadius,
                transform: nil
            )
            CATransaction.commit()
        }

        private func updateAnimation(reduceMotion: Bool, isActive: Bool, cycleSeconds: TimeInterval) {
            if reduceMotion || !isActive {
                if isAnimating {
                    gradientLayer.removeAnimation(forKey: pulseKey)
                    isAnimating = false
                }
                gradientLayer.opacity = 1
                return
            }

            guard !isAnimating else { return }
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 0.55
            pulse.toValue = 1.0
            pulse.duration = cycleSeconds
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.isRemovedOnCompletion = false
            gradientLayer.add(pulse, forKey: pulseKey)
            isAnimating = true
        }
    }
}

final class GradientBorderView: NSView {
    var layoutHandler: ((CGRect) -> Void)?

    override func layout() {
        super.layout()
        layoutHandler?(bounds)
    }
}
