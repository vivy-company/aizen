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
    var childToolCalls: [ToolCall] = []

    @State private var isExpanded: Bool
    @State private var userExpanded: Bool = false
    @State private var isHovering: Bool = false
    @State private var completedAt: Date? = nil
    @Environment(\.colorScheme) private var colorScheme

    init(toolCall: ToolCall, currentIterationId: String? = nil, onOpenDetails: ((ToolCall) -> Void)? = nil, agentSession: AgentSession? = nil, onOpenInEditor: ((String) -> Void)? = nil, childToolCalls: [ToolCall] = []) {
        self.toolCall = toolCall
        self.currentIterationId = currentIterationId
        self.onOpenDetails = onOpenDetails
        self.agentSession = agentSession
        self.onOpenInEditor = onOpenInEditor
        self.childToolCalls = childToolCalls

        let isCurrentIteration = currentIterationId == nil || toolCall.iterationId == currentIterationId

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
    
    private var toolAccentColor: Color {
        toolCall.resolvedKind.accentColor
    }
    
    private var blockBackground: Color {
        colorScheme == .dark ? Color(white: 0.11) : Color(white: 0.97)
    }
    
    private var headerBackground: Color {
        colorScheme == .dark ? Color(white: 0.13) : Color(white: 0.95)
    }
    
    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
            
            if isExpanded && (hasContent || !childToolCalls.isEmpty) {
                Divider()
                    .opacity(0.3)
                
                expandedContent
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(blockBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(borderColor, lineWidth: 0.5)
        )
        .overlay(alignment: .leading) {
            accentStripe
        }
        .shadow(
            color: .black.opacity(colorScheme == .dark ? 0.2 : 0.06),
            radius: isHovering ? 4 : 2,
            x: 0,
            y: 1
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu { contextMenuContent }
        .onChange(of: toolCall.status) { oldStatus, newStatus in
            if oldStatus == .inProgress && newStatus != .inProgress && completedAt == nil {
                completedAt = Date()
            }
        }
        .onAppear {
            if toolCall.status != .inProgress && completedAt == nil {
                completedAt = Date()
            }
        }
    }
    
    private var accentStripe: some View {
        UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 6)
            .fill(toolAccentColor)
            .frame(width: 3)
    }
    
    private var headerRow: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
                userExpanded = true
            }
        }) {
            HStack(spacing: 8) {
                toolIcon
                    .foregroundStyle(toolAccentColor)
                    .frame(width: 14, height: 14)

                Text(toolCall.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if isTaskToolCall && !childToolCalls.isEmpty {
                    Text("(\(childToolCalls.count))")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 6)
                
                CompactStatusBadge(status: toolCall.status)

                if hasContent || !childToolCalls.isEmpty {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(headerBackground)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !shouldShowContent {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 12, height: 12)
                    Text("Running...")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            if shouldShowContent, isTaskToolCall && !childToolCalls.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(childToolCalls) { child in
                        ToolCallView(
                            toolCall: child,
                            currentIterationId: currentIterationId,
                            agentSession: agentSession,
                            onOpenInEditor: onOpenInEditor,
                            childToolCalls: []
                        )
                    }
                }
            }

            if shouldShowContent, hasContent {
                inlineContentView

                if let path = filePath, onOpenInEditor != nil {
                    Button(action: { onOpenInEditor?(path) }) {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.text")
                            Text("Open in Editor")
                        }
                        .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                    .padding(.top, 4)
                }
            }
        }
    }
    
    @ViewBuilder
    private var contextMenuContent: some View {
        if onOpenDetails != nil {
            Button {
                onOpenDetails?(toolCall)
            } label: {
                Label("Open Details", systemImage: "arrow.up.right.square")
            }
        }

        if let output = copyableOutput {
            Button {
                Clipboard.copy(output)
            } label: {
                Label("Copy Output", systemImage: "doc.on.doc")
            }
        }

        if let path = filePath {
            Button {
                Clipboard.copy(path)
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

    // MARK: - Copyable Output

    private var copyableOutput: String? {
        toolCall.copyableOutputText
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
    
    private func extractCommand() -> String? {
        guard let rawInput = toolCall.rawInput?.value as? [String: Any] else { return nil }
        return rawInput["command"] as? String
    }
    
    private func extractExitCode() -> Int? {
        guard let rawOutput = toolCall.rawOutput?.value as? [String: Any] else { return nil }
        return rawOutput["exitCode"] as? Int ?? rawOutput["exit_code"] as? Int
    }

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
            InlineTerminalView(
                terminalId: terminal.terminalId,
                agentSession: agentSession,
                command: extractCommand(),
                exitCode: extractExitCode()
            )
        }
    }

    @ViewBuilder
    private func inlineContentBlock(_ block: ContentBlock) -> some View {
        switch block {
        case .text(let textContent):
            if toolCall.kind == .execute {
                CommandBlock(
                    command: extractCommand() ?? toolCall.title,
                    output: textContent.text,
                    exitCode: resolvedExitCodeStatus,
                    isStreaming: toolCall.status == .inProgress,
                    startTime: toolCall.timestamp,
                    endTime: completedAt
                )
            } else if let semanticBlock = parseSemanticContent(textContent.text) {
                semanticBlock
            } else {
                HighlightedTextContentView(
                    text: textContent.text,
                    filePath: filePath,
                    allowHighlight: isFinal,
                    allowSelection: isFinal
                )
            }
        default:
            EmptyView()
        }
    }
    
    private var resolvedExitCodeStatus: ExitCodeStatus {
        if toolCall.status == .inProgress {
            return .running
        }
        if let code = extractExitCode() {
            return code == 0 ? .success : .failure(code: code)
        }
        switch toolCall.status {
        case .completed: return .success
        case .failed: return .failure(code: 1)
        default: return .unknown
        }
    }
    
    @ViewBuilder
    private func parseSemanticContent(_ text: String) -> SemanticBlockView? {
        if let result = EmojiSemanticPatterns.detect(in: text), !result.content.isEmpty {
            return SemanticBlockView(type: result.type, content: result.content)
        }
        return nil
    }

    // MARK: - Status

    private var statusColor: Color {
        ToolStatusPresentation.color(for: toolCall.status)
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
        let displayText = parsedContent.code.isEmpty ? " " : parsedContent.code
        MonospaceTextPanel(
            text: displayText,
            attributedText: shouldHighlight ? highlightedText : nil,
            maxHeight: 150,
            font: .system(size: 10, design: .monospaced),
            backgroundColor: Color(nsColor: .textBackgroundColor),
            padding: 6,
            allowsSelection: allowSelection
        )
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
