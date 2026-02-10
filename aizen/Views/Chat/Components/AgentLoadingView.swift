//
//  AgentLoadingView.swift
//  aizen
//
//  Loading view shown when agent session is starting
//

import AppKit
import SwiftUI
import Combine

struct AgentLoadingView: View {
    let agentName: String

    @State private var currentTipIndex: Int = 0
    @State private var tipOpacity: Double = 1.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private let tips = [
        "⌘D to split terminal right, ⇧⌘D to split down",
        "⇧⌘A to switch between active environments",
        "⇧⌘Z to toggle Zen Mode for distraction-free coding",
        "Type @ to mention files or folders in chat",
        "Drag files into the chat to attach them",
        "Use / to access slash commands",
        "Each environment has its own terminal, chat, and browser",
        "Right-click files to send them to the agent",
        "Git linked environments let you work on multiple branches at once",
        "⌘P to open command palette for quick navigation",
    ]

    private let tipRotationTimer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Animated agent icon with spinning ring
            ZStack {
                // Spinning arc (Core Animation)
                SpinningArcView(
                    color: NSColor(agentColor),
                    lineWidth: 3,
                    isActive: scenePhase == .active && !reduceMotion,
                    duration: 3
                )
                .frame(width: 88, height: 88)

                // Icon container
                Circle()
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .frame(width: 72, height: 72)

                // Agent icon
                AgentIconView(agent: agentName, size: 40)
            }

            // Loading text
            VStack(spacing: 8) {
                Text("Starting \(displayName)")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(tips[currentTipIndex])
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .opacity(tipOpacity)
                    .animation(.easeInOut(duration: 0.3), value: tipOpacity)
                    .frame(height: 20)
            }
            .multilineTextAlignment(.center)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(tipRotationTimer) { _ in
            rotateTip()
        }
    }

    // MARK: - Computed Properties

    private var displayName: String {
        if let meta = AgentRegistry.shared.getMetadata(for: agentName) {
            return meta.name
        }
        return agentName.capitalized
    }

    private var agentColor: Color {
        switch agentName.lowercased() {
        case "claude":
            return Color(red: 0.85, green: 0.55, blue: 0.35)  // Claude orange/tan
        case "gemini":
            return Color(red: 0.4, green: 0.5, blue: 0.9)  // Gemini blue
        case "codex", "openai":
            return Color(red: 0.3, green: 0.75, blue: 0.65)  // OpenAI teal
        case "copilot":
            return Color(red: 0.25, green: 0.6, blue: 0.9)  // Copilot blue
        case "droid":
            return Color(red: 0.933, green: 0.376, blue: 0.094)  // Droid orange (#EE6018)
        case "kimi":
            return Color(red: 0.6, green: 0.4, blue: 0.8)  // Kimi purple
        default:
            return Color.accentColor
        }
    }

    // MARK: - Animations

    private func rotateTip() {
        // Fade out
        withAnimation(.easeOut(duration: 0.2)) {
            tipOpacity = 0
        }

        // Change tip and fade in
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            currentTipIndex = (currentTipIndex + 1) % tips.count
            withAnimation(.easeIn(duration: 0.3)) {
                tipOpacity = 1
            }
        }
    }
}

private struct SpinningArcView: NSViewRepresentable {
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

private final class ArcSpinnerView: NSView {
    var layoutHandler: ((CGRect) -> Void)?

    override func layout() {
        super.layout()
        layoutHandler?(bounds)
    }
}

#Preview {
    AgentLoadingView(agentName: "claude")
        .frame(width: 400, height: 500)
}
