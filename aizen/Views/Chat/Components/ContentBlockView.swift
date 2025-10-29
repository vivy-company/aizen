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
            return AnyView(ACPResourceView(uri: resourceContent.resource.uri, mimeType: resourceContent.resource.mimeType, text: resourceContent.resource.text))

        case .audio(let audioContent):
            return AnyView(
                Text("Audio content: \(audioContent.mimeType)")
                    .foregroundColor(.secondary)
            )

        case .embeddedResource(let embeddedContent):
            return AnyView(
                VStack(alignment: .leading, spacing: 8) {
                    Text("Embedded: \(embeddedContent.uri)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    ForEach(0..<embeddedContent.content.count, id: \.self) { index in
                        contentView(for: embeddedContent.content[index])
                    }
                }
            )

        case .diff(let diffContent):
            return AnyView(
                VStack(alignment: .leading, spacing: 4) {
                    if let path = diffContent.path {
                        Text("File: \(path)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Text("Diff content")
                        .font(.system(.body, design: .monospaced))
                }
            )

        case .terminalEmbed(let terminalContent):
            return AnyView(
                VStack(alignment: .leading, spacing: 4) {
                    Text("Terminal: \(terminalContent.command)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(terminalContent.output)
                        .font(.system(.body, design: .monospaced))
                    if let exitCode = terminalContent.exitCode {
                        Text("Exit code: \(exitCode)")
                            .font(.caption2)
                            .foregroundColor(exitCode == 0 ? .green : .red)
                    }
                }
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
                Image(systemName: iconName)
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

    private var iconName: String {
        switch block {
        case .resource:
            return "doc.fill"
        case .image:
            return "photo.fill"
        case .audio:
            return "waveform"
        case .embeddedResource:
            return "doc.badge.gearshape.fill"
        case .diff:
            return "doc.text.magnifyingglass"
        case .terminalEmbed:
            return "terminal.fill"
        default:
            return "doc.fill"
        }
    }

    private var fileName: String {
        switch block {
        case .resource(let content):
            if let url = URL(string: content.resource.uri) {
                return url.lastPathComponent
            }
            return String(localized: "chat.attachment.file")
        case .image:
            return String(localized: "chat.content.image")
        case .audio:
            return String(localized: "chat.content.audio")
        case .embeddedResource(let content):
            if let url = URL(string: content.uri) {
                return url.lastPathComponent
            }
            return String(localized: "chat.content.resource")
        case .diff(let content):
            return content.path ?? String(localized: "chat.content.diff")
        case .terminalEmbed:
            return String(localized: "chat.attachment.terminalOutput")
        default:
            return String(localized: "chat.attachment.generic")
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
            if let url = URL(string: content.resource.uri) {
                return url.lastPathComponent
            }
            return String(localized: "chat.attachment.file")
        case .image:
            return String(localized: "chat.content.image")
        case .audio:
            return String(localized: "chat.content.audio")
        case .embeddedResource(let content):
            if let url = URL(string: content.uri) {
                return url.lastPathComponent
            }
            return String(localized: "chat.content.resource")
        case .diff(let content):
            return content.path ?? String(localized: "chat.content.diff")
        case .terminalEmbed:
            return String(localized: "chat.attachment.terminalOutput")
        default:
            return String(localized: "chat.attachment.generic")
        }
    }
}
