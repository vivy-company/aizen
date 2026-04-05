//
//  DiffView+Support.swift
//  aizen
//
//  Created by OpenAI Codex on 06.04.26.
//

import AppKit
import SwiftUI
import VVCode

extension DiffView {
    var theme: VVTheme {
        AppearanceSettings.resolvedTheme(colorScheme: colorScheme)
    }

    var configuration: VVConfiguration {
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)

        return VVConfiguration.default
            .with(font: font)
            .with(showLineNumbers: true)
            .with(showGutter: true)
            .with(showGitGutter: false)
            .with(wrapLines: true)
    }

    var unifiedDiff: String {
        if let diffOutput {
            return diffOutput
        }

        guard let preloadedLines else {
            return ""
        }

        return Self.unifiedDiff(from: preloadedLines)
    }

    var displayDiff: String {
        let collapsed = Self.collapsedDeletedFileSections(in: unifiedDiff)
        return Self.normalizeDiffPaths(in: collapsed, repoPath: repoPath)
    }

    var filePaths: [String] {
        Self.filePaths(in: displayDiff)
    }

    var showsDeletedFilePlaceholder: Bool {
        guard let preloadedLines, !preloadedLines.isEmpty else {
            return false
        }

        let hasDeletedMarker = preloadedLines.contains { line in
            line.type == DiffLineType.header && line.content.hasPrefix("deleted file mode")
        }
        let hasDeletedLines = preloadedLines.contains { line in
            line.type == DiffLineType.deleted
        }
        let hasAdditionsOrContext = preloadedLines.contains { line in
            line.type == DiffLineType.added || line.type == DiffLineType.context
        }
        return (hasDeletedMarker || hasDeletedLines) && !hasAdditionsOrContext
    }

    var deletedFilePlaceholderView: some View {
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
