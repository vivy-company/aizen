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
    var agentSession: AgentSession? = nil

    @State private var isExpanded: Bool

    init(toolCall: ToolCall, onOpenDetails: ((ToolCall) -> Void)? = nil, agentSession: AgentSession? = nil) {
        self.toolCall = toolCall
        self.onOpenDetails = onOpenDetails
        self.agentSession = agentSession
        // Default expanded for edit, diff, and terminal content
        let shouldExpand = toolCall.kind == .edit || toolCall.kind == .delete ||
            toolCall.content.contains { content in
                switch content {
                case .diff, .terminal: return true
                default: return false
                }
            }
        self._isExpanded = State(initialValue: shouldExpand)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header row (always visible)
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
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

                    // Expand indicator if has content
                    if hasContent {
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
            if isExpanded && hasContent {
                inlineContentView
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(backgroundColor)
        .cornerRadius(3)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Inline Content

    private var hasContent: Bool {
        !toolCall.content.isEmpty
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
            InlineDiffView(diff: diff)
        case .terminal(let terminal):
            InlineTerminalView(terminalId: terminal.terminalId, agentSession: agentSession)
        }
    }

    @ViewBuilder
    private func inlineContentBlock(_ block: ContentBlock) -> some View {
        switch block {
        case .text(let textContent):
            ScrollView {
                Text(textContent.text)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 150)
            .padding(6)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(4)
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
        guard toolCall.kind == .edit else { return nil }

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
        switch resource {
        case .text(let textResource):
            ACPResourceView(uri: textResource.uri, mimeType: textResource.mimeType, text: textResource.text)
        case .blob(let blobResource):
            ACPResourceView(uri: blobResource.uri, mimeType: blobResource.mimeType, text: nil)
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


// MARK: - Inline Diff Line (local to avoid conflict with DiffView.DiffLine)

private enum InlineDiffLineType {
    case context
    case added
    case deleted
    case separator
}

private struct InlineDiffLine: Identifiable {
    let id = UUID()
    let type: InlineDiffLineType
    let content: String
}

// MARK: - Inline Diff View

struct InlineDiffView: View {
    let diff: ToolCallDiff

    @AppStorage("terminalFontName") private var terminalFontName = "Menlo"
    @AppStorage("terminalFontSize") private var terminalFontSize = 12.0

    private var fontSize: CGFloat {
        max(terminalFontSize - 2, 9)
    }

    private var diffLines: [InlineDiffLine] {
        computeUnifiedDiff(oldText: diff.oldText, newText: diff.newText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // File path header
            HStack(spacing: 4) {
                Image(systemName: "doc.badge.plus")
                    .font(.system(size: 9))
                Text(URL(fileURLWithPath: diff.path).lastPathComponent)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(.secondary)

            // Diff content
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(diffLines) { line in
                        diffLineView(line)
                    }
                }
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 200)
            .padding(8)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(6)
        }
    }

    @ViewBuilder
    private func diffLineView(_ line: InlineDiffLine) -> some View {
        switch line.type {
        case .context:
            Text("  \(line.content)")
                .font(.custom(terminalFontName, size: fontSize))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .added:
            Text("+ \(line.content)")
                .font(.custom(terminalFontName, size: fontSize))
                .foregroundColor(.green)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.1))
        case .deleted:
            Text("- \(line.content)")
                .font(.custom(terminalFontName, size: fontSize))
                .foregroundColor(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.1))
        case .separator:
            Text(line.content)
                .font(.custom(terminalFontName, size: fontSize))
                .foregroundColor(.cyan)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)
        }
    }

    // MARK: - Diff Computation

    private func computeUnifiedDiff(oldText: String?, newText: String, contextLines: Int = 3) -> [InlineDiffLine] {
        let oldLines = (oldText ?? "").split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let newLines = newText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        // Compute LCS to find matching lines
        let lcs = longestCommonSubsequence(oldLines, newLines)

        // Build edit script
        var edits: [(type: InlineDiffLineType, content: String)] = []
        var oldIdx = 0
        var newIdx = 0
        var lcsIdx = 0

        while oldIdx < oldLines.count || newIdx < newLines.count {
            if lcsIdx < lcs.count && oldIdx < oldLines.count && newIdx < newLines.count &&
               oldLines[oldIdx] == lcs[lcsIdx] && newLines[newIdx] == lcs[lcsIdx] {
                // Matching line (context)
                edits.append((.context, oldLines[oldIdx]))
                oldIdx += 1
                newIdx += 1
                lcsIdx += 1
            } else if oldIdx < oldLines.count && (lcsIdx >= lcs.count || oldLines[oldIdx] != lcs[lcsIdx]) {
                // Line removed from old
                edits.append((.deleted, oldLines[oldIdx]))
                oldIdx += 1
            } else if newIdx < newLines.count {
                // Line added in new
                edits.append((.added, newLines[newIdx]))
                newIdx += 1
            }
        }

        // Generate unified diff with context
        return generateHunks(edits: edits, contextLines: contextLines)
    }

    private func longestCommonSubsequence(_ a: [String], _ b: [String]) -> [String] {
        let m = a.count
        let n = b.count
        guard m > 0 && n > 0 else { return [] }

        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)

        for i in 1...m {
            for j in 1...n {
                if a[i - 1] == b[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1] + 1
                } else {
                    dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }

        // Backtrack to find LCS
        var result: [String] = []
        var i = m, j = n
        while i > 0 && j > 0 {
            if a[i - 1] == b[j - 1] {
                result.append(a[i - 1])
                i -= 1
                j -= 1
            } else if dp[i - 1][j] > dp[i][j - 1] {
                i -= 1
            } else {
                j -= 1
            }
        }
        return result.reversed()
    }

    private func generateHunks(edits: [(type: InlineDiffLineType, content: String)], contextLines: Int) -> [InlineDiffLine] {
        var result: [InlineDiffLine] = []

        // Find ranges of changes
        var changeIndices: [Int] = []
        for (i, edit) in edits.enumerated() {
            if edit.type != .context {
                changeIndices.append(i)
            }
        }

        if changeIndices.isEmpty {
            return [] // No changes
        }

        // Group changes into hunks
        var hunks: [[Int]] = []
        var currentHunk: [Int] = []

        for idx in changeIndices {
            if currentHunk.isEmpty {
                currentHunk.append(idx)
            } else if idx - currentHunk.last! <= contextLines * 2 + 1 {
                currentHunk.append(idx)
            } else {
                hunks.append(currentHunk)
                currentHunk = [idx]
            }
        }
        if !currentHunk.isEmpty {
            hunks.append(currentHunk)
        }

        // Generate output for each hunk
        for (hunkIdx, hunk) in hunks.enumerated() {
            let startIdx = max(0, hunk.first! - contextLines)
            let endIdx = min(edits.count - 1, hunk.last! + contextLines)

            // Add separator between hunks
            if hunkIdx > 0 {
                result.append(InlineDiffLine(type: .separator, content: "···"))
            }

            // Add lines in this hunk
            for i in startIdx...endIdx {
                let edit = edits[i]
                result.append(InlineDiffLine(type: edit.type, content: edit.content))
            }
        }

        return result
    }
}

// MARK: - Inline Terminal View

struct InlineTerminalView: View {
    let terminalId: String
    var agentSession: AgentSession?

    @AppStorage("terminalFontName") private var terminalFontName = "Menlo"
    @AppStorage("terminalFontSize") private var terminalFontSize = 12.0

    @State private var output: String = ""
    @State private var isRunning: Bool = false
    @State private var loadTask: Task<Void, Never>?

    private var fontSize: CGFloat {
        max(terminalFontSize - 2, 9) // Slightly smaller for inline view
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Terminal output with ANSI colors
            ScrollView {
                if output.isEmpty {
                    Text("Waiting for output...")
                        .font(.custom(terminalFontName, size: fontSize))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(ANSIParser.parse(output))
                        .font(.custom(terminalFontName, size: fontSize))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxHeight: 150)
            .padding(8)
            .background(Color(red: 0.11, green: 0.11, blue: 0.13))
            .cornerRadius(6)

            // Running indicator below
            if isRunning {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 12, height: 12)
                    Text("Running...")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
        }
        .onAppear {
            startLoading()
        }
        .onDisappear {
            loadTask?.cancel()
        }
    }

    private func startLoading() {
        loadTask = Task {
            guard let session = agentSession else { return }

            // Poll for output
            for _ in 0..<120 { // 60 seconds max
                if Task.isCancelled { break }

                output = await session.getTerminalOutput(terminalId: terminalId) ?? ""
                isRunning = await session.isTerminalRunning(terminalId: terminalId)

                if !isRunning && !output.isEmpty {
                    break
                }

                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
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
            content: [.content(.text(TextContent(text: "import SwiftUI\n\nstruct ContentView: View {\n    var body: some View {\n        Text(\"Hello, World!\")\n    }\n}")))],
            locations: nil,
            rawInput: nil,
            rawOutput: nil
        ))

        ToolCallView(toolCall: ToolCall(
            toolCallId: "2",
            title: "Execute: swift build",
            kind: .execute,
            status: .inProgress,
            content: [.content(.text(TextContent(text: "$ swift build\nBuilding for production...")))],
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
            content: [.content(.text(TextContent(text: "Error: File not found")))],
            locations: nil,
            rawInput: nil,
            rawOutput: nil
        ))

        ToolCallView(toolCall: ToolCall(
            toolCallId: "5",
            title: "Apply diff",
            kind: .edit,
            status: .completed,
            content: [.diff(ToolCallDiff(path: "file.swift", oldText: "import SwiftUI\n\nstruct View: View {", newText: "import SwiftUI\nimport Combine\n\nstruct View: View {"))],
            locations: nil,
            rawInput: nil,
            rawOutput: nil
        ))
    }
    .padding()
    .frame(width: 700)
}
