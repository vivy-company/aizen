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
            if let nsImage = configuredSymbolImage(
                NSImage(systemSymbolName: symbolName, accessibilityDescription: nil),
                pointSize: size,
                weight: .semibold
            ) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
            } else {
                Image(systemName: symbolName)
                    .font(.system(size: size, weight: .semibold))
                    .frame(width: size, height: size)
            }
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
            assetSymbolIcon("claude")
        case "gemini":
            assetSymbolIcon("gemini")
        case "codex", "openai":
            assetSymbolIcon("openai")
        case "copilot":
            assetSymbolIcon("copilot")
        case "droid":
            assetSymbolIcon("droid")
        case "kimi":
            assetSymbolIcon("kimi")
        case "opencode":
            assetSymbolIcon("opencode")
        case "vibe", "mistral":
            assetSymbolIcon("mistral")
        case "qwen":
            assetSymbolIcon("qwen")
        default:
            defaultIcon
        }
    }

    @ViewBuilder
    private func assetSymbolIcon(_ assetName: String) -> some View {
        if let baseImage = NSImage(named: assetName),
           let configured = configuredSymbolImage(baseImage, pointSize: size, weight: .semibold) {
            Image(nsImage: configured)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            Image(assetName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        }
    }

    private func configuredSymbolImage(_ image: NSImage?, pointSize: CGFloat, weight: NSFont.Weight) -> NSImage? {
        guard let image else { return nil }
        let config = NSImage.SymbolConfiguration(
            pointSize: max(12, pointSize),
            weight: weight,
            scale: .medium
        )
        if let configured = image.withSymbolConfiguration(config) {
            return configured
        }
        return image
    }

    private var defaultIcon: some View {
        Image(systemName: "brain.head.profile")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
    }
}
