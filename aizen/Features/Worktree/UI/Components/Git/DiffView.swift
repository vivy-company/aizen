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
    let diffOutput: String?

    // Input mode 2: Pre-parsed lines (for single-file view)
    let preloadedLines: [DiffLine]?

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

    @Environment(\.colorScheme) var colorScheme

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
}
