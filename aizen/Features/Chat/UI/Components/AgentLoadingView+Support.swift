//
//  AgentLoadingView+Support.swift
//  aizen
//

import SwiftUI

extension AgentLoadingView {
    var displayName: String {
        if let meta = AgentRegistry.shared.getMetadata(for: agentName) {
            return meta.name
        }
        return agentName.capitalized
    }

    var agentColor: Color {
        switch agentName.lowercased() {
        case "claude-acp":
            return Color(red: 0.85, green: 0.55, blue: 0.35)
        case "gemini":
            return Color(red: 0.4, green: 0.5, blue: 0.9)
        case "codex-acp":
            return Color(red: 0.3, green: 0.75, blue: 0.65)
        case "github-copilot-cli":
            return Color(red: 0.25, green: 0.6, blue: 0.9)
        case "factory-droid":
            return Color(red: 0.933, green: 0.376, blue: 0.094)
        case "kimi":
            return Color(red: 0.6, green: 0.4, blue: 0.8)
        default:
            return Color.accentColor
        }
    }

    func rotateTip() {
        withAnimation(.easeOut(duration: 0.2)) {
            tipOpacity = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            currentTipIndex = (currentTipIndex + 1) % tips.count
            withAnimation(.easeIn(duration: 0.3)) {
                tipOpacity = 1
            }
        }
    }
}
