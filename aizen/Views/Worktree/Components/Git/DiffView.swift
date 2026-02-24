//
//  DiffView.swift
//  aizen
//
//  Unified diff renderer backed by VVDiffView.
//

import AppKit
import SwiftUI
import VVCode

struct DiffView: View {
    // Input mode 1: Raw diff string (for multi-file view)
    private let diffOutput: String?

    // Input mode 2: Pre-parsed lines (for single-file view)
    private let preloadedLines: [DiffLine]?

    let fontSize: Double
    let fontFamily: String
    let repoPath: String
    let showFileHeaders: Bool
    let scrollToFile: String?
    let onFileVisible: ((String) -> Void)?
    let onOpenFile: ((String) -> Void)?
    let commentedLines: Set<String>
    let onAddComment: ((DiffLine, String) -> Void)?

    @AppStorage("editorTheme") private var editorTheme: String = "Aizen Dark"
    @AppStorage("editorThemeLight") private var editorThemeLight: String = "Aizen Light"
    @AppStorage("editorUsePerAppearanceTheme") private var usePerAppearanceTheme = false
    @Environment(\.colorScheme) private var colorScheme

    // Init for raw diff output (used by GitChangesOverlayView)
    init(
        diffOutput: String,
        fontSize: Double,
        fontFamily: String,
        repoPath: String = "",
        scrollToFile: String? = nil,
        onFileVisible: ((String) -> Void)? = nil,
        onOpenFile: ((String) -> Void)? = nil,
        commentedLines: Set<String> = [],
        onAddComment: ((DiffLine, String) -> Void)? = nil
    ) {
        self.diffOutput = diffOutput
        self.preloadedLines = nil
        self.fontSize = fontSize
        self.fontFamily = fontFamily
        self.repoPath = repoPath
        self.showFileHeaders = true
        self.scrollToFile = scrollToFile
        self.onFileVisible = onFileVisible
        self.onOpenFile = onOpenFile
        self.commentedLines = commentedLines
        self.onAddComment = onAddComment
    }

    // Init for pre-parsed lines (used by FileDiffSectionView)
    init(
        lines: [DiffLine],
        fontSize: Double,
        fontFamily: String,
        repoPath: String = "",
        showFileHeaders: Bool = false,
        commentedLines: Set<String> = [],
        onAddComment: ((DiffLine, String) -> Void)? = nil
    ) {
        self.diffOutput = nil
        self.preloadedLines = lines
        self.fontSize = fontSize
        self.fontFamily = fontFamily
        self.repoPath = repoPath
        self.showFileHeaders = showFileHeaders
        self.scrollToFile = nil
        self.onFileVisible = nil
        self.onOpenFile = nil
        self.commentedLines = commentedLines
        self.onAddComment = onAddComment
    }

    private var effectiveThemeName: String {
        guard usePerAppearanceTheme else { return editorTheme }
        return colorScheme == .dark ? editorTheme : editorThemeLight
    }

    private var theme: VVTheme {
        GhosttyThemeParser.loadVVTheme(named: effectiveThemeName)
            ?? (colorScheme == .dark ? .defaultDark : .defaultLight)
    }

    private var configuration: VVConfiguration {
        let font = NSFont(name: fontFamily, size: fontSize)
            ?? .monospacedSystemFont(ofSize: fontSize, weight: .regular)

        return VVConfiguration.default
            .with(font: font)
            .with(showLineNumbers: true)
            .with(showGutter: true)
            .with(showGitGutter: false)
            .with(wrapLines: true)
    }

    private var unifiedDiff: String {
        if let diffOutput {
            return diffOutput
        }

        guard let preloadedLines else {
            return ""
        }

        return Self.unifiedDiff(from: preloadedLines)
    }

    private var displayDiff: String {
        let collapsed = Self.collapsedDeletedFileSections(in: unifiedDiff)
        return Self.normalizeDiffPaths(in: collapsed, repoPath: repoPath)
    }

    private var filePaths: [String] {
        Self.filePaths(in: displayDiff)
    }

    private var showsDeletedFilePlaceholder: Bool {
        guard let preloadedLines, !preloadedLines.isEmpty else {
            return false
        }

        let hasDeletedMarker = preloadedLines.contains { line in
            line.type == .header && line.content.hasPrefix("deleted file mode")
        }
        let hasDeletedLines = preloadedLines.contains { $0.type == .deleted }
        let hasAdditionsOrContext = preloadedLines.contains { $0.type == .added || $0.type == .context }
        return (hasDeletedMarker || hasDeletedLines) && !hasAdditionsOrContext
    }

    var body: some View {
        Group {
            if showsDeletedFilePlaceholder {
                deletedFilePlaceholderView
            } else {
                VVDiffView(unifiedDiff: displayDiff)
                    .theme(theme)
                    .configuration(configuration)
                    .renderStyle(.unifiedTable)
                    .syntaxHighlighting(true)
                    .onFileHeaderActivate { path in
                        onOpenFile?(path)
                    }
            }
        }
        .onAppear {
            if let target = scrollToFile {
                onFileVisible?(target)
            } else if let first = filePaths.first {
                onFileVisible?(first)
            }
        }
        .onChange(of: scrollToFile) { _, newValue in
            if let newValue {
                onFileVisible?(newValue)
            }
        }
    }

    private var deletedFilePlaceholderView: some View {
        HStack(spacing: 8) {
            Image(systemName: "trash")
                .foregroundStyle(.secondary)
            Text("File removed. Diff content omitted.")
                .font(.system(size: max(fontSize - 1, 10)))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private static func filePaths(in diff: String) -> [String] {
        diff
            .components(separatedBy: .newlines)
            .compactMap { line in
                guard line.hasPrefix("diff --git ") else { return nil }
                let parts = line.split(separator: " ")
                guard parts.count >= 4 else { return nil }
                let bPath = String(parts[3])
                if bPath.hasPrefix("b/") {
                    return String(bPath.dropFirst(2))
                }
                return bPath
            }
    }

    private static func unifiedDiff(from lines: [DiffLine]) -> String {
        let detectedPath = detectPath(from: lines) ?? "file"
        var output: [String] = []

        output.append("diff --git a/\(detectedPath) b/\(detectedPath)")
        output.append("--- a/\(detectedPath)")
        output.append("+++ b/\(detectedPath)")

        var hasHunkHeader = false

        for line in lines {
            switch line.type {
            case .header:
                if line.content.hasPrefix("@@") {
                    output.append(line.content)
                    hasHunkHeader = true
                } else if line.content.hasPrefix("index ") ||
                            line.content.hasPrefix("new file") ||
                            line.content.hasPrefix("deleted file") ||
                            line.content.hasPrefix("Binary files") {
                    output.append(line.content)
                }
            case .added:
                if !hasHunkHeader {
                    output.append("@@ -1,1 +1,1 @@")
                    hasHunkHeader = true
                }
                output.append("+\(line.content)")
            case .deleted:
                if !hasHunkHeader {
                    output.append("@@ -1,1 +1,1 @@")
                    hasHunkHeader = true
                }
                output.append("-\(line.content)")
            case .context:
                if !hasHunkHeader {
                    output.append("@@ -1,1 +1,1 @@")
                    hasHunkHeader = true
                }
                output.append(" \(line.content)")
            }
        }

        if !hasHunkHeader {
            output.append("@@ -1,1 +1,1 @@")
        }

        return output.joined(separator: "\n")
    }

    private static func collapsedDeletedFileSections(in diff: String) -> String {
        guard diff.contains("deleted file mode") else {
            return diff
        }

        let lines = diff.components(separatedBy: .newlines)
        var preamble: [String] = []
        var chunks: [[String]] = []
        var currentChunk: [String] = []
        var hasDiffHeader = false

        for line in lines {
            if line.hasPrefix("diff --git ") {
                if hasDiffHeader {
                    chunks.append(currentChunk)
                    currentChunk = [line]
                } else {
                    hasDiffHeader = true
                    preamble = currentChunk
                    currentChunk = [line]
                }
                continue
            }
            currentChunk.append(line)
        }

        guard hasDiffHeader else {
            return diff
        }

        chunks.append(currentChunk)

        var output: [String] = preamble
        for chunk in chunks {
            if isDeletedFileChunk(chunk) {
                output.append(contentsOf: summarizedDeletedChunk(chunk))
            } else {
                output.append(contentsOf: chunk)
            }
        }
        return output.joined(separator: "\n")
    }

    private static func isDeletedFileChunk(_ chunk: [String]) -> Bool {
        chunk.contains(where: { $0.hasPrefix("deleted file mode ") }) ||
        chunk.contains(where: { $0.hasPrefix("+++ /dev/null") })
    }

    private static func summarizedDeletedChunk(_ chunk: [String]) -> [String] {
        var output: [String] = []

        if let header = chunk.first(where: { $0.hasPrefix("diff --git ") }) {
            output.append(header)
        }
        if let index = chunk.first(where: { $0.hasPrefix("index ") }) {
            output.append(index)
        }
        if let deletedMode = chunk.first(where: { $0.hasPrefix("deleted file mode ") }) {
            output.append(deletedMode)
        }
        if let oldFile = chunk.first(where: { $0.hasPrefix("--- ") }) {
            output.append(oldFile)
        }
        if let newFile = chunk.first(where: { $0.hasPrefix("+++ ") }) {
            output.append(newFile)
        } else {
            output.append("+++ /dev/null")
        }
        return output
    }

    private static func normalizeDiffPaths(in diff: String, repoPath: String) -> String {
        guard !repoPath.isEmpty else {
            return diff
        }

        let standardizedRepoPath = URL(fileURLWithPath: repoPath).standardizedFileURL.path
        guard !standardizedRepoPath.isEmpty else {
            return diff
        }

        let normalizedLines = diff.components(separatedBy: .newlines).map { line in
            if line.hasPrefix("diff --git ") {
                return normalizeDiffGitHeader(line, repoPath: standardizedRepoPath)
            }
            if line.hasPrefix("--- ") {
                let value = String(line.dropFirst(4))
                let normalized = normalizePathToken(value, repoPath: standardizedRepoPath)
                return "--- \(normalized)"
            }
            if line.hasPrefix("+++ ") {
                let value = String(line.dropFirst(4))
                let normalized = normalizePathToken(value, repoPath: standardizedRepoPath)
                return "+++ \(normalized)"
            }
            return line
        }

        return normalizedLines.joined(separator: "\n")
    }

    private static func normalizeDiffGitHeader(_ line: String, repoPath: String) -> String {
        let parts = line.split(separator: " ", omittingEmptySubsequences: false)
        guard parts.count >= 4 else {
            return line
        }

        let leftPath = normalizePathToken(String(parts[2]), repoPath: repoPath)
        let rightPath = normalizePathToken(String(parts[3]), repoPath: repoPath)
        return "diff --git \(leftPath) \(rightPath)"
    }

    private static func normalizePathToken(_ token: String, repoPath: String) -> String {
        let trimmed = token.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed == "/dev/null" {
            return trimmed
        }

        let prefix: String
        let rawPath: String
        if trimmed.hasPrefix("a/") || trimmed.hasPrefix("b/") {
            prefix = String(trimmed.prefix(2))
            rawPath = String(trimmed.dropFirst(2))
        } else {
            prefix = ""
            rawPath = trimmed
        }

        let standardizedPath: String
        if rawPath.hasPrefix("/") {
            standardizedPath = URL(fileURLWithPath: rawPath).standardizedFileURL.path
        } else {
            standardizedPath = rawPath
        }
        let relativePath: String
        if standardizedPath == repoPath {
            relativePath = "."
        } else if standardizedPath.hasPrefix(repoPath + "/") {
            relativePath = String(standardizedPath.dropFirst(repoPath.count + 1))
        } else {
            relativePath = rawPath
        }

        if prefix.isEmpty {
            return relativePath
        }
        return "\(prefix)\(relativePath)"
    }

    private static func detectPath(from lines: [DiffLine]) -> String? {
        for line in lines where line.type == .header {
            if line.content.hasPrefix("new file: ") {
                let value = line.content.replacingOccurrences(of: "new file: ", with: "")
                if !value.isEmpty {
                    return value
                }
            }
            if line.content.contains("/") {
                return line.content
            }
        }
        return nil
    }
}
