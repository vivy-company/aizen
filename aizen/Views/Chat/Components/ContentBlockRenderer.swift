//
//  ContentBlockRenderer.swift
//  aizen
//
//  Shared content block rendering across chat and tool views
//

import ACP
import SwiftUI

enum ContentBlockRenderStyle {
    case full
    case compact
}

struct ContentBlockRenderer: View {
    let block: ContentBlock
    let style: ContentBlockRenderStyle

    var body: some View {
        content
    }

    @ViewBuilder
    private var content: some View {
        switch block {
        case .text(let textContent):
            textView(textContent.text)
        case .image(let imageContent):
            imageView(data: imageContent.data, mimeType: imageContent.mimeType)
        case .resource(let resourceContent):
            resourceView(resourceContent.resource)
        case .resourceLink(let linkContent):
            resourceLinkView(linkContent)
        case .audio(let audioContent):
            audioView(mimeType: audioContent.mimeType)
        }
    }

    @ViewBuilder
    private func textView(_ text: String) -> some View {
        switch style {
        case .full:
            MessageContentView(content: text)
        case .compact:
            MonospaceTextPanel(text: text, maxHeight: 200)
        }
    }

    @ViewBuilder
    private func imageView(data: String, mimeType: String) -> some View {
        switch style {
        case .full:
            ImageAttachmentCardView(data: data)
        case .compact:
            Text(String(localized: "chat.content.imageType \(mimeType)"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func resourceView(_ resource: EmbeddedResourceType) -> some View {
        switch style {
        case .full:
            ACPResourceView(uri: resource.uri ?? "unknown", mimeType: resource.mimeType, text: resource.text)
        case .compact:
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "chat.content.resourceUri \(resource.uri ?? "unknown")"))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let text = resource.text {
                    MonospaceTextPanel(text: text, maxHeight: 150)
                }
            }
        }
    }

    @ViewBuilder
    private func resourceLinkView(_ content: ResourceLinkContent) -> some View {
        switch style {
        case .full:
            VStack(alignment: .leading, spacing: 4) {
                if let title = content.title {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                Text(content.uri)
                    .font(.caption)
                    .foregroundColor(.blue)
                if let description = content.description {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(8)
            .background(.ultraThinMaterial)
            .cornerRadius(6)
        case .compact:
            Text(String(localized: "chat.content.resourceUri \(content.uri)"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private func audioView(mimeType: String) -> some View {
        switch style {
        case .full:
            Text("Audio content: \(mimeType)")
                .foregroundColor(.secondary)
        case .compact:
            Text(String(localized: "chat.content.audioType \(mimeType)"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

}
