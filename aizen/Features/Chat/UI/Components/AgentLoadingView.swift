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

    @State var currentTipIndex: Int = 0
    @State var tipOpacity: Double = 1.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    let tips = [
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
}

#Preview {
    AgentLoadingView(agentName: "claude")
        .frame(width: 400, height: 500)
}
