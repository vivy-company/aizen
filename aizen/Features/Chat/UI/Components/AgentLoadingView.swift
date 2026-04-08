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
        "⌘K to open command palette for quick navigation",
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
        case "claude-acp":
            return Color(red: 0.85, green: 0.55, blue: 0.35)  // Claude orange/tan
        case "gemini":
            return Color(red: 0.4, green: 0.5, blue: 0.9)  // Gemini blue
        case "codex-acp":
            return Color(red: 0.3, green: 0.75, blue: 0.65)  // OpenAI teal
        case "github-copilot-cli":
            return Color(red: 0.25, green: 0.6, blue: 0.9)  // Copilot blue
        case "factory-droid":
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
#Preview {
    AgentLoadingView(agentName: "claude")
        .frame(width: 400, height: 500)
}
