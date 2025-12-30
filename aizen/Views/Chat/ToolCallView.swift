//  ToolCallView.swift
//  aizen
//
//  SwiftUI view for displaying tool execution details
//

import SwiftUI
import Foundation
import AppKit
import CodeEditLanguages
import CodeEditSourceEditor

struct ToolCallView: View {
    let toolCall: ToolCall
    var currentIterationId: String? = nil
    var onOpenDetails: ((ToolCall) -> Void)? = nil
    var agentSession: AgentSession? = nil
    var onOpenInEditor: ((String) -> Void)? = nil
    var childToolCalls: [ToolCall] = []  // Children for Task tool calls

    @State private var isExpanded: Bool
    @State private var userExpanded: Bool = false

    init(toolCall: ToolCall, currentIterationId: String? = nil, onOpenDetails: ((ToolCall) -> Void)? = nil, agentSession: AgentSession? = nil, onOpenInEditor: ((String) -> Void)? = nil, childToolCalls: [ToolCall] = []) {
        self.toolCall = toolCall
        self.currentIterationId = currentIterationId
        self.onOpenDetails = onOpenDetails
        self.agentSession = agentSession
        self.onOpenInEditor = onOpenInEditor
        self.childToolCalls = childToolCalls

        // Collapse tool calls from previous iterations
        let isCurrentIteration = currentIterationId == nil || toolCall.iterationId == currentIterationId

        // Default expanded for current iteration edit/diff content (terminal collapsed by default)
        let kind = toolCall.kind
        let shouldExpand = isCurrentIteration && (kind == .edit || kind == .delete ||
            toolCall.content.contains { content in
                switch content {
                case .diff: return true
                default: return false
                }
            })
        self._isExpanded = State(initialValue: shouldExpand)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header row (always visible)
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                    userExpanded = true
                }
            }) {
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

                    // Child count badge for Task tool calls
                    if isTaskToolCall && !childToolCalls.isEmpty {
                        Text("(\(childToolCalls.count))")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }

                    // Expand indicator if has content or children
                    if hasContent || !childToolCalls.isEmpty {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }

                    Spacer(minLength: 6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expandable content
            if isExpanded && (hasContent || !childToolCalls.isEmpty) {
                if !shouldShowContent {
                    Text("Running…")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                        .transition(.opacity)
                }

                // Child tool calls for Task (rendered inline)
                if shouldShowContent, isTaskToolCall && !childToolCalls.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(childToolCalls) { child in
                            ToolCallView(
                                toolCall: child,
                                currentIterationId: currentIterationId,
                                agentSession: agentSession,
                                onOpenInEditor: onOpenInEditor,
                                childToolCalls: []  // Children are leaf nodes
                            )
                            .padding(.leading, 12)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // Original content (for non-Task or Task's own summary)
                if shouldShowContent, hasContent {
                    inlineContentView
                        .transition(.opacity.combined(with: .move(edge: .top)))

                    // Open in Editor button for file operations
                    if let path = filePath, onOpenInEditor != nil {
                        Button(action: { onOpenInEditor?(path) }) {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.text")
                                Text("Open in Editor")
                            }
                            .font(.system(size: 10))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.blue)
                        .padding(.top, 4)
                    }
                }
            }
        }
        .background(backgroundColor)
        .cornerRadius(3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu {
            if onOpenDetails != nil {
                Button {
                    onOpenDetails?(toolCall)
                } label: {
                    Label("Open Details", systemImage: "arrow.up.right.square")
                }
            }

            if let output = copyableOutput {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(output, forType: .string)
                } label: {
                    Label("Copy Output", systemImage: "doc.on.doc")
                }
            }

            if let path = filePath {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(path, forType: .string)
                } label: {
                    Label("Copy Path", systemImage: "link")
                }

                if onOpenInEditor != nil {
                    Divider()
                    Button {
                        onOpenInEditor?(path)
                    } label: {
                        Label("Open in Editor", systemImage: "doc.text")
                    }
                }
            }
        }
    }

    // MARK: - Copyable Output

    private var copyableOutput: String? {
        var outputs: [String] = []
        for content in toolCall.content {
            switch content {
            case .content(let block):
                if case .text(let textContent) = block {
                    outputs.append(textContent.text)
                }
            case .diff(let diff):
                outputs.append(diff.newText)
            case .terminal:
                break // Terminal output handled separately
            }
        }
        let result = outputs.joined(separator: "\n\n")
        return result.isEmpty ? nil : result
    }

    // MARK: - File Path Extraction

    private var filePath: String? {
        // Check locations first
        if let path = toolCall.locations?.first?.path {
            return path
        }
        // For diff content, extract path
        for content in toolCall.content {
            if case .diff(let diff) = content {
                return diff.path
            }
        }
        // For file operations, title often contains the path
        if let kind = toolCall.kind,
           [.read, .edit, .delete, .move].contains(kind),
           toolCall.title.contains("/") {
            return toolCall.title
        }
        return nil
    }

    // MARK: - Task Detection

    /// Check if this tool call is a Task (subagent) - detected by having children
    private var isTaskToolCall: Bool {
        !childToolCalls.isEmpty
    }

    // MARK: - Inline Content

    private var hasContent: Bool {
        !toolCall.content.isEmpty
    }

    private var isFinal: Bool {
        toolCall.status == .completed || toolCall.status == .failed
    }

    private var shouldShowContent: Bool {
        isFinal || userExpanded
    }

    @ViewBuilder
    private var inlineContentView: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(toolCall.content.enumerated()), id: \.offset) { _, content in
                inlineContentItem(content)
            }
        }
    }

    @ViewBuilder
    private func inlineContentItem(_ content: ToolCallContent) -> some View {
        switch content {
        case .content(let block):
            inlineContentBlock(block)
        case .diff(let diff):
            InlineDiffView(diff: diff, allowCompute: isFinal)
        case .terminal(let terminal):
            InlineTerminalView(terminalId: terminal.terminalId, agentSession: agentSession)
        }
    }

    @ViewBuilder
    private func inlineContentBlock(_ block: ContentBlock) -> some View {
        switch block {
        case .text(let textContent):
            HighlightedTextContentView(
                text: textContent.text,
                filePath: filePath,
                allowHighlight: isFinal,
                allowSelection: isFinal
            )
        default:
            EmptyView()
        }
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
        guard toolCall.kind == .some(.edit) else { return nil }

        for block in toolCall.content {
            switch block {
            case .content(let contentBlock):
                if case .text(let content) = contentBlock {
                    let trimmed = content.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let firstLine = trimmed.split(separator: "\n").map(String.init).first, !firstLine.isEmpty {
                        return firstLine
                    }
                }
            case .diff(let diff):
                return "Modified: \(diff.path)"
            case .terminal(let terminal):
                return "Terminal: \(terminal.terminalId)"
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
                Image(systemName: toolCall.resolvedKind.symbolName)
            }
        default:
            Image(systemName: toolCall.resolvedKind.symbolName)
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
        return toolCall.resolvedKind.rawValue
    }

}

// MARK: - Highlighted Text Content View

struct HighlightedTextContentView: View {
    let text: String
    let filePath: String?
    let allowHighlight: Bool
    var allowSelection: Bool = true

    @State private var highlightedText: AttributedString?
    @AppStorage("editorTheme") private var editorTheme: String = "Aizen Dark"
    @AppStorage("editorThemeLight") private var editorThemeLight: String = "Aizen Light"
    @AppStorage("editorUsePerAppearanceTheme") private var usePerAppearanceTheme = false
    @Environment(\.colorScheme) private var colorScheme

    private var effectiveThemeName: String {
        guard usePerAppearanceTheme else { return editorTheme }
        return colorScheme == .dark ? editorTheme : editorThemeLight
    }

    private let highlighter = TreeSitterHighlighter()

    /// Extract code from markdown code fence if present, along with language hint
    private var parsedContent: (code: String, fenceLanguage: String?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check for markdown code fence: ```language\ncode\n```
        if trimmed.hasPrefix("```") {
            let lines = trimmed.components(separatedBy: "\n")
            guard lines.count >= 2 else { return (text, nil) }

            // Extract language from first line (```swift or ```)
            let firstLine = lines[0]
            let fenceLang = String(firstLine.dropFirst(3)).trimmingCharacters(in: .whitespaces)

            // Find closing fence
            var codeLines: [String] = []
            for i in 1..<lines.count {
                if lines[i].trimmingCharacters(in: .whitespaces) == "```" {
                    break
                }
                codeLines.append(lines[i])
            }

            let code = codeLines.joined(separator: "\n")
            return (code, fenceLang.isEmpty ? nil : fenceLang)
        }

        return (text, nil)
    }

    private var detectedLanguage: CodeLanguage {
        let (_, fenceLang) = parsedContent

        // First try fence language hint
        if let lang = fenceLang, !lang.isEmpty {
            return LanguageDetection.languageFromFence(lang)
        }

        // Fall back to file path detection
        guard let path = filePath else { return CodeLanguage.default }
        return LanguageDetection.detectLanguage(mimeType: nil, uri: path, content: text)
    }

    private var shouldHighlight: Bool {
        guard allowHighlight else { return false }
        if parsedContent.code.count > 4000 { return false }
        if parsedContent.code.filter({ $0 == "\n" }).count > 200 { return false }
        let (_, fenceLang) = parsedContent
        // Highlight if we have a fence language or a code file path
        if fenceLang != nil { return true }
        guard let path = filePath else { return false }
        return LanguageDetection.isCodeFile(mimeType: nil, uri: path)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            if shouldHighlight, let highlighted = highlightedText {
                let highlightedView = Text(highlighted)
                    .font(.system(size: 10, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                if allowSelection {
                    highlightedView.textSelection(.enabled)
                } else {
                    highlightedView
                }
            } else {
                let displayText = parsedContent.code.isEmpty ? " " : parsedContent.code
                let plainView = Text(displayText)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if allowSelection {
                    plainView.textSelection(.enabled)
                } else {
                    plainView
                }
            }
        }
        .frame(maxHeight: 150)
        .padding(6)
        .background(Color(nsColor: .textBackgroundColor))
        .cornerRadius(4)
        .task(id: allowHighlight ? text : "highlight-disabled") {
            guard shouldHighlight else { return }
            await performHighlight()
        }
    }

    private func performHighlight() async {
        let (code, _) = parsedContent
        do {
            let theme = GhosttyThemeParser.loadTheme(named: effectiveThemeName) ?? defaultTheme()
            let attributed = try await highlighter.highlightCode(
                code,
                language: detectedLanguage,
                theme: theme
            )
            highlightedText = attributed
        } catch {
            highlightedText = nil
        }
    }

    private func defaultTheme() -> EditorTheme {
        let bg = NSColor(red: 0.12, green: 0.12, blue: 0.18, alpha: 1.0)
        let fg = NSColor(red: 0.8, green: 0.84, blue: 0.96, alpha: 1.0)

        return EditorTheme(
            text: .init(color: fg),
            insertionPoint: fg,
            invisibles: .init(color: .systemGray),
            background: bg,
            lineHighlight: bg.withAlphaComponent(0.05),
            selection: .selectedTextBackgroundColor,
            keywords: .init(color: .systemPurple),
            commands: .init(color: .systemBlue),
            types: .init(color: .systemYellow),
            attributes: .init(color: .systemRed),
            variables: .init(color: .systemCyan),
            values: .init(color: .systemOrange),
            numbers: .init(color: .systemOrange),
            strings: .init(color: .systemGreen),
            characters: .init(color: .systemGreen),
            comments: .init(color: .systemGray)
        )
    }
}
