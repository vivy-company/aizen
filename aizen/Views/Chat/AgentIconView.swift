//
//  AgentIconView.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 27.10.25.
//

import SwiftUI

/// Shared agent icon view builder
struct AgentIconView: View {
    let iconType: AgentIconType?
    let agentName: String?
    let size: CGFloat

    init(iconType: AgentIconType, size: CGFloat) {
        self.iconType = iconType
        self.agentName = nil
        self.size = size
    }

    init(agent: String, size: CGFloat) {
        self.iconType = nil
        self.agentName = agent
        self.size = size
    }

    init(metadata: AgentMetadata, size: CGFloat) {
        self.iconType = metadata.iconType
        self.agentName = nil
        self.size = size
    }

    var body: some View {
        if let iconType = iconType {
            iconForType(iconType)
        } else if let agentName = agentName {
            iconForAgentName(agentName)
        } else {
            defaultIcon
        }
    }

    @ViewBuilder
    private func iconForType(_ type: AgentIconType) -> some View {
        switch type {
        case .builtin(let name):
            iconForBuiltinName(name)
        case .sfSymbol(let symbolName):
            Image(systemName: symbolName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        case .customImage(let imageData):
            if let nsImage = NSImage(data: imageData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
            } else {
                defaultIcon
            }
        }
    }

    @ViewBuilder
    private func iconForAgentName(_ agent: String) -> some View {
        // Check if metadata exists
        if let metadata = AgentRegistry.shared.getMetadata(for: agent) {
            iconForType(metadata.iconType)
        } else {
            // Legacy fallback
            iconForBuiltinName(agent.lowercased())
        }
    }

    @ViewBuilder
    private func iconForBuiltinName(_ name: String) -> some View {
        switch name.lowercased() {
        case "claude":
            Image("claude")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        case "gemini":
            Image("gemini")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        case "codex", "openai":
            Image("openai")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        case "droid":
            Image("droid")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        case "kimi":
            Image("kimi")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        case "opencode":
            Image("opencode")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        case "vibe", "mistral":
            Image("mistral")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        case "qwen":
            Image("qwen")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        default:
            defaultIcon
        }
    }

    private var defaultIcon: some View {
        Image(systemName: "brain.head.profile")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
    }
}
