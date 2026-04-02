//
//  AgentIconView.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 27.10.25.
//

import SwiftUI

/// Shared agent icon view builder
struct AgentIconView: View {
    let metadata: AgentMetadata?
    let iconType: AgentIconType?
    let agentName: String?
    let size: CGFloat

    init(iconType: AgentIconType, size: CGFloat) {
        self.metadata = nil
        self.iconType = iconType
        self.agentName = nil
        self.size = size
    }

    init(agent: String, size: CGFloat) {
        self.metadata = nil
        self.iconType = nil
        self.agentName = agent
        self.size = size
    }

    init(metadata: AgentMetadata, size: CGFloat) {
        self.metadata = metadata
        self.iconType = metadata.iconType
        self.agentName = nil
        self.size = size
    }

    var body: some View {
        if let metadata {
            iconForMetadata(metadata)
        } else if let iconType = iconType {
            iconForType(iconType)
        } else if let agentName = agentName {
            if let metadata = AgentRegistry.shared.getMetadata(for: agentName) {
                iconForMetadata(metadata)
            } else {
                defaultIcon
            }
        } else {
            defaultIcon
        }
    }

    @ViewBuilder
    private func iconForMetadata(_ metadata: AgentMetadata) -> some View {
        if metadata.isRegistry, metadata.registryIconURL != nil {
            RegistryRemoteIconView(iconURL: metadata.registryIconURL, size: size) {
                iconForType(metadata.iconType)
            }
        } else {
            iconForType(metadata.iconType)
        }
    }

    @ViewBuilder
    private func iconForType(_ type: AgentIconType) -> some View {
        switch type {
        case .builtin:
            defaultIcon
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
