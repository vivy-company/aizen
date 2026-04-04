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
    let renderStyle: VVDiffRenderStyle
    let showFileHeaders: Bool
    let scrollToFile: String?
    let onFileVisible: ((String) -> Void)?
    let onOpenFile: ((String) -> Void)?
    let commentedLines: Set<String>
    let onAddComment: ((DiffLine, String) -> Void)?

    @Environment(\.colorScheme) private var colorScheme

    // Init for raw diff output (used by GitChangesOverlayView)
    init(
        diffOutput: String,
        fontSize: Double,
        fontFamily: String,
        repoPath: String = "",
        renderStyle: VVDiffRenderStyle = .inline,
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
        self.renderStyle = renderStyle
        self.showFileHeaders = true
        self.scrollToFile = scrollToFile
        self.onFileVisible = onFileVisible
        self.onOpenFile = onOpenFile
        self.commentedLines = commentedLines
        self.onAddComment = onAddComment
    }

    // Init for pre-parsed lines
    init(
        lines: [DiffLine],
        fontSize: Double,
        fontFamily: String,
        repoPath: String = "",
        renderStyle: VVDiffRenderStyle = .inline,
        showFileHeaders: Bool = false,
        commentedLines: Set<String> = [],
        onAddComment: ((DiffLine, String) -> Void)? = nil
    ) {
        self.diffOutput = nil
        self.preloadedLines = lines
        self.fontSize = fontSize
        self.fontFamily = fontFamily
        self.repoPath = repoPath
        self.renderStyle = renderStyle
        self.showFileHeaders = showFileHeaders
        self.scrollToFile = nil
        self.onFileVisible = nil
        self.onOpenFile = nil
        self.commentedLines = commentedLines
        self.onAddComment = onAddComment
    }

    private var theme: VVTheme {
        AppearanceSettings.resolvedTheme(colorScheme: colorScheme)
    }

    private var configuration: VVConfiguration {
        // Match the upstream VVDevKit diff playground, which renders with the
        // system monospace font and avoids file-header glyph corruption.
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)

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
                    .renderStyle(renderStyle)
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
        .task(id: scrollToFile) {
            guard let scrollToFile else { return }
            guard scrollToFile != filePaths.first else { return }
            await MainActor.run {
                onFileVisible?(scrollToFile)
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

}
