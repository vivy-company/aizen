//
//  ShimmerEffect.swift
//  aizen
//
//  Shimmer animation effect for loading states
//

import AppKit
import SwiftUI

// Core Animation based shimmer for low CPU/GPU churn.
struct ShimmerEffect: ViewModifier {
    var isActive: Bool = true
    var bandSize: CGFloat = 0.25
    var duration: CFTimeInterval = 1.8
    var baseOpacity: CGFloat = 0.12
    var highlightOpacity: CGFloat = 0.9

    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        if isActive && !reduceMotion && scenePhase == .active {
            content
                .overlay(
                    ShimmerOverlay(
                        bandSize: bandSize,
                        duration: duration,
                        baseOpacity: baseOpacity,
                        highlightOpacity: highlightOpacity,
                        layoutDirection: layoutDirection
                    )
                    .allowsHitTesting(false)
                    .mask(content)
                )
        } else {
            content
        }
    }
}

private struct ShimmerOverlay: NSViewRepresentable {
    let bandSize: CGFloat
    let duration: CFTimeInterval
    let baseOpacity: CGFloat
    let highlightOpacity: CGFloat
    let layoutDirection: LayoutDirection

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> ShimmerLayerView {
        let view = ShimmerLayerView()
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: ShimmerLayerView, context: Context) {
        context.coordinator.update(
            in: nsView,
            bandSize: bandSize,
            duration: duration,
            baseOpacity: baseOpacity,
            highlightOpacity: highlightOpacity,
            layoutDirection: layoutDirection
        )
    }

    final class Coordinator {
        private let gradientLayer = CAGradientLayer()
        private var isAnimating = false
        private weak var hostView: ShimmerLayerView?
        private let shimmerKey = "aizen.shimmer.translate"
        private var travelWidth: CGFloat = 0
        private var currentDuration: CFTimeInterval = 0
        private var currentLayoutDirection: LayoutDirection = .leftToRight
        private var pendingDuration: CFTimeInterval = 0
        private var pendingLayoutDirection: LayoutDirection = .leftToRight

        func attach(to view: ShimmerLayerView) {
            guard hostView == nil else { return }
            hostView = view
            view.wantsLayer = true
            view.layer = CALayer()
            view.layer?.masksToBounds = true
            view.layer?.addSublayer(gradientLayer)
            gradientLayer.type = .axial
            gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
            gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
            view.layoutHandler = { [weak self] bounds in
                self?.layout(in: bounds)
                self?.startIfPossible()
            }
        }

        func update(
            in view: ShimmerLayerView,
            bandSize: CGFloat,
            duration: CFTimeInterval,
            baseOpacity: CGFloat,
            highlightOpacity: CGFloat,
            layoutDirection: LayoutDirection
        ) {
            if hostView == nil {
                attach(to: view)
            }
            pendingDuration = duration
            pendingLayoutDirection = layoutDirection

            let base = NSColor.white.withAlphaComponent(baseOpacity)
            let highlight = NSColor.white.withAlphaComponent(highlightOpacity)
            gradientLayer.colors = [base.cgColor, highlight.cgColor, base.cgColor]
            let clampedBand = max(min(bandSize, 0.45), 0.1)
            gradientLayer.locations = [
                NSNumber(value: Double(0.5 - clampedBand)),
                NSNumber(value: 0.5),
                NSNumber(value: Double(0.5 + clampedBand))
            ]

            if let scale = view.window?.backingScaleFactor {
                view.layer?.contentsScale = scale
                gradientLayer.contentsScale = scale
            }

            layout(in: view.bounds)
            startIfPossible()
        }

        private func layout(in bounds: CGRect) {
            guard !bounds.isEmpty else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let expandedWidth = bounds.width * 3
            gradientLayer.frame = CGRect(x: -bounds.width, y: 0, width: expandedWidth, height: bounds.height)
            travelWidth = bounds.width
            CATransaction.commit()
        }

        private func startIfPossible() {
            pendingDuration = max(pendingDuration, 0.1)
            guard travelWidth > 0 else { return }
            updateAnimation(duration: pendingDuration, layoutDirection: pendingLayoutDirection)
        }

        private func updateAnimation(duration: CFTimeInterval, layoutDirection: LayoutDirection) {
            guard travelWidth > 0 else { return }
            let needsRestart = !isAnimating ||
                abs(currentDuration - duration) > 0.01 ||
                currentLayoutDirection != layoutDirection

            guard needsRestart else { return }

            gradientLayer.removeAnimation(forKey: shimmerKey)

            let animation = CABasicAnimation(keyPath: "transform.translation.x")
            let distance = travelWidth
            if layoutDirection == .rightToLeft {
                animation.fromValue = Double(distance)
                animation.toValue = Double(-distance)
            } else {
                animation.fromValue = Double(-distance)
                animation.toValue = Double(distance)
            }
            animation.duration = duration
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animation.repeatCount = .infinity
            animation.isRemovedOnCompletion = false

            gradientLayer.add(animation, forKey: shimmerKey)
            isAnimating = true
            currentDuration = duration
            currentLayoutDirection = layoutDirection
        }
    }
}

private final class ShimmerLayerView: NSView {
    var layoutHandler: ((CGRect) -> Void)?

    override func layout() {
        super.layout()
        layoutHandler?(bounds)
    }
}
