//
//  RegistryRemoteIconView.swift
//  aizen
//

import AppKit
import SwiftUI

struct RegistryRemoteIconView<Fallback: View>: View {
    let iconURL: String?
    let size: CGFloat
    @ViewBuilder let fallback: () -> Fallback

    @State private var iconData: Data?

    var body: some View {
        Group {
            if let iconData {
                renderedIcon(for: iconData)
            } else {
                fallback()
            }
        }
        .frame(width: size, height: size)
        .task(id: iconURL) {
            iconData = await RegistryAgentIconCache.shared.iconData(for: iconURL)
        }
    }

    @ViewBuilder
    private func renderedIcon(for data: Data) -> some View {
        if let image = templateAwareImage(from: data) {
            if RegistryAgentIconCache.isSVGData(data) {
                Image(nsImage: image)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(Color.primary)
            } else {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
        } else {
            fallback()
        }
    }

    private func templateAwareImage(from data: Data) -> NSImage? {
        guard let image = NSImage(data: data)?.copy() as? NSImage else {
            return nil
        }
        if RegistryAgentIconCache.isSVGData(data) {
            image.isTemplate = true
        }
        return image
    }
}
