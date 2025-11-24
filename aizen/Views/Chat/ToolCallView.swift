//
//  ToolCallView.swift
//  aizen
//
//  SwiftUI view for displaying tool execution details
//

import SwiftUI
import Foundation

struct ToolCallView: View {
    let toolCall: ToolCall
    var onOpenDetails: ((ToolCall) -> Void)? = nil

    var body: some View {
        Button(action: { onOpenDetails?(toolCall) }) {
            HStack(spacing: 8) {
                // Status dot
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)

                // Tool icon
                toolIcon
                    .foregroundColor(.secondary)
                    .frame(width: 12, height: 12)

                // Title
                Text(toolCall.title)
                    .font(.system(size: 11))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                if let preview = editPreviewText {
                    Text(preview)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(backgroundColor)
        .cornerRadius(3)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Status

    private var statusText: String {
        switch toolCall.status {
        case .pending: return String(localized: "chat.tool.status.pending")
        case .inProgress: return String(localized: "chat.tool.status.running")
        case .completed: return String(localized: "chat.tool.status.done")
        case .failed: return String(localized: "chat.tool.status.failed")
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)

            Text(statusText)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(statusColor)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(statusColor.opacity(0.12))
        .cornerRadius(10)
    }

    private var statusColor: Color {
        switch toolCall.status {
        case .pending: return .yellow
        case .inProgress: return .blue
        case .completed: return .green
        case .failed: return .red
        }
    }

    private var editPreviewText: String? {
        guard toolCall.kind == .edit else { return nil }

        for block in toolCall.content {
            switch block {
            case .text(let content):
                let trimmed = content.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if let firstLine = trimmed.split(separator: "\n").map(String.init).first, !firstLine.isEmpty {
                    return firstLine
                }
            default:
                continue
            }
        }

        return nil
    }

    // MARK: - Tool Icon

    @ViewBuilder
    private var toolIcon: some View {
        switch toolCall.kind {
        case .read, .edit, .delete, .move:
            // For file operations, use FileIconView if title looks like a path
            if toolCall.title.contains("/") || toolCall.title.contains(".") {
                FileIconView(path: toolCall.title, size: 12)
            } else {
                fallbackIcon
            }
        case .search:
            Image(systemName: "magnifyingglass")
        case .execute:
            Image(systemName: "terminal")
        case .think:
            Image(systemName: "brain")
        case .fetch:
            Image(systemName: "arrow.down.circle")
        case .switchMode:
            Image(systemName: "arrow.left.arrow.right")
        case .plan:
            Image(systemName: "list.bullet.clipboard")
        case .exitPlanMode:
            Image(systemName: "checkmark.circle")
        case .other:
            Image(systemName: "wrench.and.screwdriver")
        }
    }

    private var fallbackIcon: some View {
        Group {
            switch toolCall.kind {
            case .read:
                Image(systemName: "doc.text")
            case .edit:
                Image(systemName: "pencil")
            case .delete:
                Image(systemName: "trash")
            case .move:
                Image(systemName: "arrow.right.doc.on.clipboard")
            default:
                Image(systemName: "doc")
            }
        }
    }

    // MARK: - Colors

    private var backgroundColor: Color {
        Color(.controlBackgroundColor).opacity(0.2)
    }

    private var borderColor: Color {
        Color.gray.opacity(0.2)
    }

    private var displayTitle: String {
        let trimmed = toolCall.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return toolCall.kind.rawValue
    }

}

// MARK: - Content Block View

struct ContentBlockView: View {
    let block: ContentBlock
    @State private var isCopied: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                contentTypeLabel
                Spacer()
                copyButton
            }

            contentBody
        }
        .padding(8)
        .background(Color(.textBackgroundColor))
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.gray.opacity(0.15), lineWidth: 0.5)
        )
    }

    private var contentTypeLabel: some View {
        Group {
            switch block {
            case .text:
                Label(String(localized: "chat.content.textOutput"), systemImage: "text.alignleft")
            case .image:
                Label(String(localized: "chat.content.image"), systemImage: "photo")
            case .resource:
                Label(String(localized: "chat.content.resource"), systemImage: "doc.badge.gearshape")
            case .resourceLink:
                Label(String(localized: "chat.content.resourceLink"), systemImage: "link.circle")
            case .audio:
                Label(String(localized: "chat.content.audio"), systemImage: "waveform")
            }
        }
        .font(.system(size: 10))
        .foregroundColor(.secondary)
    }

    private var copyButton: some View {
        Button(action: copyContent) {
            HStack(spacing: 3) {
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                Text(isCopied ? String(localized: "chat.content.copied") : String(localized: "chat.content.copy"))
            }
            .font(.system(size: 10))
            .foregroundColor(isCopied ? .green : .blue)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var contentBody: some View {
        switch block {
            case .text(let content):
                TextContentView(text: content.text)
            case .image(let content):
                ACPImageView(data: content.data, mimeType: content.mimeType)
            case .resource(let content):
                resourceView(for: content.resource)
            case .audio(let content):
                Text(String(format: String(localized: "chat.content.audioType"), content.mimeType))
                    .foregroundColor(.secondary)
            case .resourceLink(let content):
                VStack(alignment: .leading, spacing: 4) {
                    if let title = content.title {
                        Text(title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    Text(content.uri)
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            default:
                Text("Unsupported content type")
            }
    }

    private func copyContent() {
        let textToCopy: String

        switch block {
        case .text(let content):
            textToCopy = content.text
        case .image:
            textToCopy = String(localized: "chat.content.imageContent")
        case .resource(let content):
            let uri: String
            let text: String?
            switch content.resource {
            case .text(let textResource):
                uri = textResource.uri
                text = textResource.text
            case .blob(let blobResource):
                uri = blobResource.uri
                text = nil
            }
            textToCopy = text ?? uri
        case .resourceLink(let content):
            textToCopy = content.uri
        case .audio(let content):
            textToCopy = String(format: String(localized: "chat.content.audioContent"), content.mimeType)
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(textToCopy, forType: .string)

        isCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isCopied = false
        }
    }

    @ViewBuilder
    private func resourceView(for resource: EmbeddedResourceType) -> some View {
        let uri: String
        let mimeType: String?
        let text: String?
        switch resource {
        case .text(let textResource):
            uri = textResource.uri
            mimeType = textResource.mimeType
            text = textResource.text
        case .blob(let blobResource):
            uri = blobResource.uri
            mimeType = blobResource.mimeType
            text = nil
        }
        ACPResourceView(uri: uri, mimeType: mimeType, text: text)
    }
}

// MARK: - Text Content View

struct TextContentView: View {
    let text: String

    var body: some View {
        ScrollView {
            if isDiff {
                DiffContentView(text: text)
            } else if isTerminalOutput {
                TerminalContentView(text: text)
            } else {
                Text(text)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxHeight: 300)
    }

    private var isDiff: Bool {
        text.contains("+++") || text.contains("---") ||
        text.split(separator: "\n").contains { line in
            line.hasPrefix("+") || line.hasPrefix("-") || line.hasPrefix("@@")
        }
    }

    private var isTerminalOutput: Bool {
        text.contains("$") && (text.contains("\n") || text.count > 50)
    }
}

// MARK: - Diff Content View

struct DiffContentView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(lines, id: \.self) { line in
                diffLine(line)
            }
        }
        .font(.system(size: 11, design: .monospaced))
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var lines: [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    private func diffLine(_ line: String) -> some View {
        Text(line)
            .foregroundColor(lineColor(for: line))
            .background(lineBackground(for: line))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func lineColor(for line: String) -> Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") {
            return .green
        } else if line.hasPrefix("-") && !line.hasPrefix("---") {
            return .red
        } else if line.hasPrefix("@@") {
            return .blue
        }
        return .primary
    }

    private func lineBackground(for line: String) -> Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") {
            return Color.green.opacity(0.1)
        } else if line.hasPrefix("-") && !line.hasPrefix("---") {
            return Color.red.opacity(0.1)
        }
        return Color.clear
    }
}

// MARK: - Terminal Content View

struct TerminalContentView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .foregroundColor(lineColor(for: line))
            }
        }
        .font(.system(size: 11, design: .monospaced))
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(6)
        .background(Color.black.opacity(0.85))
        .cornerRadius(3)
    }

    private var lines: [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    private func lineColor(for line: String) -> Color {
        if line.contains("error") || line.contains("Error") || line.contains("ERROR") {
            return .red
        } else if line.contains("warning") || line.contains("Warning") || line.contains("WARN") {
            return .yellow
        } else if line.contains("success") || line.contains("Success") || line.contains("✓") {
            return .green
        } else if line.hasPrefix("$") || line.hasPrefix(">") {
            return .cyan
        }
        return .white
    }
}


// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        ToolCallView(toolCall: ToolCall(
            toolCallId: "1",
            title: "Read file: main.swift",
            kind: .read,
            status: .completed,
            content: [.text(TextContent(text: "import SwiftUI\n\nstruct ContentView: View {\n    var body: some View {\n        Text(\"Hello, World!\")\n    }\n}", annotations: nil, _meta: nil))],
            locations: nil,
            rawInput: nil,
            rawOutput: nil
        ))

        ToolCallView(toolCall: ToolCall(
            toolCallId: "2",
            title: "Execute: swift build",
            kind: .execute,
            status: .inProgress,
            content: [.text(TextContent(text: "$ swift build\nBuilding for production...", annotations: nil, _meta: nil))],
            locations: nil,
            rawInput: nil,
            rawOutput: nil
        ))

        ToolCallView(toolCall: ToolCall(
            toolCallId: "3",
            title: "Search for TODO comments",
            kind: .search,
            status: .pending,
            content: [],
            locations: nil,
            rawInput: nil,
            rawOutput: nil
        ))

        ToolCallView(toolCall: ToolCall(
            toolCallId: "4",
            title: "Edit file: Config.swift",
            kind: .edit,
            status: .failed,
            content: [.text(TextContent(text: "Error: File not found", annotations: nil, _meta: nil))],
            locations: nil,
            rawInput: nil,
            rawOutput: nil
        ))

        ToolCallView(toolCall: ToolCall(
            toolCallId: "5",
            title: "Apply diff",
            kind: .edit,
            status: .completed,
            content: [.text(TextContent(text: "--- a/file.swift\n+++ b/file.swift\n@@ -1,3 +1,4 @@\n import SwiftUI\n+import Combine\n \n struct View: View {", annotations: nil, _meta: nil))],
            locations: nil,
            rawInput: nil,
            rawOutput: nil
        ))
    }
    .padding()
    .frame(width: 700)
}
