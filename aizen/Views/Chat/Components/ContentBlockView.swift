//
//  ContentBlockView.swift
//  aizen
//
//  Advanced content block rendering for ACP types
//

import SwiftUI

// MARK: - Advanced Content Block View

struct ACPContentBlockView: View {
    let blocks: [ContentBlock]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                contentView(for: block)
            }
        }
    }

    private func contentView(for block: ContentBlock) -> AnyView {
        switch block {
        case .text(let textContent):
            return AnyView(MessageContentView(content: textContent.text))

        case .image(let imageContent):
            return AnyView(ACPImageView(data: imageContent.data, mimeType: imageContent.mimeType))

        case .resource(let resourceContent):
            // Handle resource union type (text or blob)
            let uri: String
            let mimeType: String?
            let text: String?

            switch resourceContent.resource {
            case .text(let textResource):
                uri = textResource.uri
                mimeType = textResource.mimeType
                text = textResource.text
            case .blob(let blobResource):
                uri = blobResource.uri
                mimeType = blobResource.mimeType
                text = nil
            }

            return AnyView(ACPResourceView(uri: uri, mimeType: mimeType, text: text))

        case .resourceLink(let linkContent):
            return AnyView(
                VStack(alignment: .leading, spacing: 4) {
                    if let title = linkContent.title {
                        Text(title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    Text(linkContent.uri)
                        .font(.caption)
                        .foregroundColor(.blue)
                    if let description = linkContent.description {
                        Text(description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(8)
                .background(.ultraThinMaterial)
                .cornerRadius(6)
            )

        case .audio(let audioContent):
            return AnyView(
                Text("Audio content: \(audioContent.mimeType)")
                    .foregroundColor(.secondary)
            )
        }
    }
}

// MARK: - Attachment Chip View

struct AttachmentChipView: View {
    let block: ContentBlock
    @State private var showingContent = false

    var body: some View {
        Button {
            showingContent = true
        } label: {
            HStack(spacing: 6) {
                attachmentIcon
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                Text(fileName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingContent) {
            AttachmentDetailView(block: block)
        }
    }

    @ViewBuilder
    private var attachmentIcon: some View {
        switch block {
        case .resource(let content):
            resourceIcon(for: content.resource)
        case .resourceLink(let content):
            if let url = URL(string: content.uri) {
                FileIconView(path: url.path, size: 10)
            } else {
                Image(systemName: "link.circle.fill")
            }
        case .text:
            Image(systemName: "doc.text.fill")
        case .image:
            Image(systemName: "photo.fill")
        case .audio:
            Image(systemName: "waveform")
        }
    }

    @ViewBuilder
    private func resourceIcon(for resource: EmbeddedResourceType) -> some View {
        let uri = getResourceUri(from: resource)
        if let url = URL(string: uri) {
            FileIconView(path: url.path, size: 10)
        } else {
            Image(systemName: "doc.fill")
        }
    }

    private func getResourceUri(from resource: EmbeddedResourceType) -> String {
        switch resource {
        case .text(let textResource):
            return textResource.uri
        case .blob(let blobResource):
            return blobResource.uri
        }
    }

    private func resourceName(for resource: EmbeddedResourceType) -> String {
        let uri = getResourceUri(from: resource)
        if let url = URL(string: uri) {
            return url.lastPathComponent
        }
        return String(localized: "chat.attachment.file")
    }

    private var fileName: String {
        switch block {
        case .resource(let content):
            return resourceName(for: content.resource)
        case .resourceLink(let content):
            if let url = URL(string: content.uri) {
                return url.lastPathComponent
            }
            return content.name
        case .image:
            return String(localized: "chat.content.image")
        case .audio:
            return String(localized: "chat.content.audio")
        case .text:
            return String(localized: "chat.content.text")
        }
    }
}

// MARK: - Attachment Detail View

struct AttachmentDetailView: View {
    let block: ContentBlock
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(.ultraThinMaterial)

            Divider()

            ScrollView {
                ACPContentBlockView(blocks: [block])
                    .padding()
            }
        }
        .frame(width: 700, height: 500)
    }

    private var title: String {
        switch block {
        case .resource(let content):
            return resourceName(for: content.resource)
        case .resourceLink(let content):
            return content.title ?? content.name
        case .image:
            return String(localized: "chat.content.image")
        case .audio:
            return String(localized: "chat.content.audio")
        case .text:
            return String(localized: "chat.content.text")
        }
    }

    private func resourceName(for resource: EmbeddedResourceType) -> String {
        let uri = getResourceUri(from: resource)
        if let url = URL(string: uri) {
            return url.lastPathComponent
        }
        return String(localized: "chat.attachment.file")
    }

    private func getResourceUri(from resource: EmbeddedResourceType) -> String {
        switch resource {
        case .text(let textResource):
            return textResource.uri
        case .blob(let blobResource):
            return blobResource.uri
        }
    }
}
