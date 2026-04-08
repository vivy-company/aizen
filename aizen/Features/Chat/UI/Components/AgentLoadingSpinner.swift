//
//  AgentLoadingSpinner.swift
//  aizen
//

import AppKit
import Combine
import SwiftUI

struct SpinningArcView: NSViewRepresentable {
    let color: NSColor
    let lineWidth: CGFloat
    let isActive: Bool
    let duration: CFTimeInterval

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> ArcSpinnerView {
        let view = ArcSpinnerView()
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: ArcSpinnerView, context: Context) {
        context.coordinator.update(in: nsView, color: color, lineWidth: lineWidth, isActive: isActive, duration: duration)
    }

    final class Coordinator {
        private let shapeLayer = CAShapeLayer()
        private var isAnimating = false
        private weak var hostView: ArcSpinnerView?
        private let rotationKey = "aizen.spinner.rotation"

        func attach(to view: ArcSpinnerView) {
            guard hostView == nil else { return }
            hostView = view
            view.wantsLayer = true
            view.layer = CALayer()
            view.layer?.addSublayer(shapeLayer)
            shapeLayer.fillColor = nil
            shapeLayer.lineCap = .round
            view.layoutHandler = { [weak self] bounds in
                self?.layout(in: bounds)
            }
        }

        func update(in view: ArcSpinnerView, color: NSColor, lineWidth: CGFloat, isActive: Bool, duration: CFTimeInterval) {
            if hostView == nil {
                attach(to: view)
            }
            shapeLayer.strokeColor = color.cgColor
            shapeLayer.lineWidth = lineWidth

            if let scale = view.window?.backingScaleFactor {
                view.layer?.contentsScale = scale
                shapeLayer.contentsScale = scale
            }

            layout(in: view.bounds)
            updateAnimation(isActive: isActive, duration: duration)
        }

        private func layout(in bounds: CGRect) {
            guard !bounds.isEmpty else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            shapeLayer.frame = bounds
            let inset = max(shapeLayer.lineWidth / 2, 0.5)
            let rect = bounds.insetBy(dx: inset, dy: inset)
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let radius = min(rect.width, rect.height) / 2
            let startAngle = -CGFloat.pi / 2
            let endAngle = startAngle + CGFloat.pi * 2 * 0.3
            let path = CGMutablePath()
            path.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
            shapeLayer.path = path
            CATransaction.commit()
        }

        private func updateAnimation(isActive: Bool, duration: CFTimeInterval) {
            if !isActive {
                if isAnimating {
                    shapeLayer.removeAnimation(forKey: rotationKey)
                    isAnimating = false
                }
                return
            }

            guard !isAnimating else { return }
            let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
            rotation.fromValue = 0
            rotation.toValue = -Double.pi * 2
            rotation.duration = duration
            rotation.timingFunction = CAMediaTimingFunction(name: .linear)
            rotation.repeatCount = .infinity
            rotation.isRemovedOnCompletion = false
            shapeLayer.add(rotation, forKey: rotationKey)
            isAnimating = true
        }
    }
}

final class ArcSpinnerView: NSView {
    var layoutHandler: ((CGRect) -> Void)?

    override func layout() {
        super.layout()
        layoutHandler?(bounds)
    }
}
