//
//  ToolCallView.swift
//  aizen
//
//  SwiftUI view for displaying tool execution details
//

import SwiftUI

struct ToolCallView: View {
    let toolCall: ToolCall
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 6) {
                    // Status dot
                    Circle()
                        .fill(statusColor)
                        .frame(width: 5, height: 5)

                    // Tool icon
                    toolIcon
                        .foregroundColor(.secondary)
                        .frame(width: 12, height: 12)

                    // Title
                    Text(toolCall.title)
                        .font(.system(size: 11))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    // Minimal status text
                    Text(statusText)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)

                    Spacer()

                    // Expand indicator (only show if has content)
                    if !toolCall.content.isEmpty {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())

            // Expanded content
            if isExpanded && !toolCall.content.isEmpty {
                Divider()
                    .padding(.vertical, 2)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(toolCall.content.enumerated()), id: \.offset) { _, block in
                        ContentBlockView(block: block)
                    }
                }
                .padding(8)
            }
        }
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

    private var statusColor: Color {
        switch toolCall.status {
        case .pending: return .yellow
        case .inProgress: return .blue
        case .completed: return .green
        case .failed: return .red
        }
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
        Color(.controlBackgroundColor).opacity(0.3)
    }

    private var borderColor: Color {
        Color.gray.opacity(0.2)
    }

    // MARK: - Timestamp

    private var formattedTimestamp: String? {
        // Note: ToolCall doesn't include timestamp in current types
        // This is a placeholder for future enhancement
        nil
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
            case .audio:
                Label(String(localized: "chat.content.audio"), systemImage: "waveform")
            case .embeddedResource:
                Label(String(localized: "chat.content.embeddedResource"), systemImage: "doc.badge.gearshape.fill")
            case .diff:
                Label(String(localized: "chat.content.diff"), systemImage: "doc.text.magnifyingglass")
            case .terminalEmbed:
                Label(String(localized: "chat.content.terminal"), systemImage: "terminal")
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

    private var contentBody: some View {
        Group {
            switch block {
            case .text(let content):
                TextContentView(text: content.text)
            case .image(let content):
                ACPImageView(data: content.data, mimeType: content.mimeType)
            case .resource(let content):
                ACPResourceView(uri: content.resource.uri, mimeType: content.resource.mimeType, text: content.resource.text)
            case .audio(let content):
                Text(String(format: String(localized: "chat.content.audioType"), content.mimeType))
                    .foregroundColor(.secondary)
            case .embeddedResource(let content):
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(format: String(localized: "chat.content.embedded"), content.uri))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            case .diff(let content):
                VStack(alignment: .leading, spacing: 4) {
                    if let path = content.path {
                        Text(String(format: String(localized: "chat.content.file"), path))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Text("chat.content.diffContent", bundle: .main)
                        .font(.system(.body, design: .monospaced))
                }
            case .terminalEmbed(let content):
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(format: String(localized: "chat.content.terminalCommand"), content.command))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(content.output)
                        .font(.system(.body, design: .monospaced))
                }
            }
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
            textToCopy = content.resource.text ?? content.resource.uri
        case .audio(let content):
            textToCopy = String(format: String(localized: "chat.content.audioContent"), content.mimeType)
        case .embeddedResource(let content):
            textToCopy = content.uri
        case .diff(let content):
            textToCopy = "Old: \(content.oldText)\nNew: \(content.newText)"
        case .terminalEmbed(let content):
            textToCopy = content.output
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(textToCopy, forType: .string)

        isCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isCopied = false
        }
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
            content: [.text(TextContent(text: "import SwiftUI\n\nstruct ContentView: View {\n    var body: some View {\n        Text(\"Hello, World!\")\n    }\n}"))]
        ))

        ToolCallView(toolCall: ToolCall(
            toolCallId: "2",
            title: "Execute: swift build",
            kind: .execute,
            status: .inProgress,
            content: [.text(TextContent(text: "$ swift build\nBuilding for production..."))]
        ))

        ToolCallView(toolCall: ToolCall(
            toolCallId: "3",
            title: "Search for TODO comments",
            kind: .search,
            status: .pending,
            content: []
        ))

        ToolCallView(toolCall: ToolCall(
            toolCallId: "4",
            title: "Edit file: Config.swift",
            kind: .edit,
            status: .failed,
            content: [.text(TextContent(text: "Error: File not found"))]
        ))

        ToolCallView(toolCall: ToolCall(
            toolCallId: "5",
            title: "Apply diff",
            kind: .edit,
            status: .completed,
            content: [.text(TextContent(text: "--- a/file.swift\n+++ b/file.swift\n@@ -1,3 +1,4 @@\n import SwiftUI\n+import Combine\n \n struct View: View {"))]
        ))
    }
    .padding()
    .frame(width: 700)
}
