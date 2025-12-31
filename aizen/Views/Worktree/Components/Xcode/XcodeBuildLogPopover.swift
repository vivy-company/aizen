//
//  XcodeBuildLogPopover.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 10.12.25.
//

import SwiftUI
import AppKit

struct XcodeBuildLogPopover: View {
    let log: String
    let duration: TimeInterval?
    let worktree: Worktree?
    let onRetry: (() -> Void)?
    let onDismiss: (() -> Void)?
    private let lines: [String]

    @State private var showingSendToAgent = false
    @State private var showCopiedFeedback = false
    @State private var showFullLog = false

    init(
        log: String,
        duration: TimeInterval?,
        worktree: Worktree? = nil,
        onRetry: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.log = log
        self.duration = duration
        self.worktree = worktree
        self.onRetry = onRetry
        self.onDismiss = onDismiss
        self.lines = log.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            header

            Divider()

            // Log content
            logContent

            Divider()

            // Action buttons
            actionBar
        }
        .frame(width: 600, height: 400)
        .sheet(isPresented: $showingSendToAgent) {
            SendToAgentSheet(
                worktree: worktree,
                attachment: .buildError(buildErrorMarkdown),
                onDismiss: { showingSendToAgent = false },
                onSend: { onDismiss?() }
            )
        }
        .sheet(isPresented: $showFullLog) {
            fullLogSheet
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
            Text("Build Failed")
                .font(.headline)

            Spacer()

            if let duration = duration {
                Text(String(format: "%.1fs", duration))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    @ViewBuilder
    private var actionBar: some View {
        HStack(spacing: 12) {
            // Copy button
            Button {
                copyToClipboard()
            } label: {
                Label(showCopiedFeedback ? "Copied" : "Copy", systemImage: showCopiedFeedback ? "checkmark" : "doc.on.doc")
            }
            .disabled(log.isEmpty)

            if truncatedLines {
                Button {
                    showFullLog = true
                } label: {
                    Label("Open Full Log", systemImage: "arrow.up.left.and.arrow.down.right")
                }
            }

            // Send to agent button
            if worktree != nil {
                Button {
                    showingSendToAgent = true
                } label: {
                    Label("Send to Agent", systemImage: "paperplane")
                }
                .disabled(log.isEmpty)
            }

            Spacer()

            // Retry button
            if let onRetry = onRetry {
                Button {
                    onDismiss?()
                    onRetry()
                } label: {
                    Label("Retry Build", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }

    private func copyToClipboard() {
        Clipboard.copy(log)

        showCopiedFeedback = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            showCopiedFeedback = false
        }
    }

    private var buildErrorMarkdown: String {
        """
        ## Xcode Build Error

        The build failed with the following errors:

        ```
        \(log)
        ```

        Please help me fix these build errors.
        """
    }

    @ViewBuilder
    private var logContent: some View {
        if log.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(displayLines.enumerated()), id: \.offset) { _, line in
                        let text = String(line)
                        Text(text)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(color(for: text))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if truncatedLines {
                        Text("… truncated, showing first \(displayLines.count) of \(totalLines) lines")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.top, 6)
                    }
                }
                .padding()
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack {
            Spacer()
            Text("No build log available")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var fullLogSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Full Build Log")
                    .font(.headline)
                Spacer()
                Button("Copy All") { copyToClipboard() }
                    .disabled(log.isEmpty)
                Button("Close") { showFullLog = false }
            }
            .padding()

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(fullLines.indices, id: \.self) { idx in
                        let line = fullLines[idx]
                        Text(line)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(color(for: line))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
            }
        }
        .frame(minWidth: 800, minHeight: 600)
    }

    // MARK: - Log Rendering Helpers

    private var fullLines: [String] { lines }

    private var totalLines: Int {
        fullLines.count
    }

    private var displayLines: ArraySlice<String> {
        fullLines.prefix(maxPreviewLines)
    }

    private var truncatedLines: Bool {
        totalLines > maxPreviewLines
    }

    private let maxPreviewLines = 600

    private func color(for line: String) -> Color {
        if line.contains("error:") {
            return .red
        } else if line.contains("warning:") {
            return .orange
        } else {
            return .primary
        }
    }
}

// MARK: - Error Summary View

struct BuildErrorSummaryView: View {
    let errors: [BuildError]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(errors.prefix(5).enumerated()), id: \.offset) { _, error in
                errorRow(error)
            }

            if errors.count > 5 {
                Text("+ \(errors.count - 5) more errors")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func errorRow(_ error: BuildError) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: errorIcon(for: error.type))
                .foregroundStyle(errorColor(for: error.type))
                .font(.system(size: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(error.message)
                    .font(.system(size: 11))
                    .lineLimit(2)

                if let file = error.file {
                    HStack(spacing: 4) {
                        Text(file)
                        if let line = error.line {
                            Text(":\(line)")
                        }
                    }
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func errorIcon(for type: BuildError.ErrorType) -> String {
        switch type {
        case .error: return "xmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .note: return "info.circle.fill"
        }
    }

    private func errorColor(for type: BuildError.ErrorType) -> Color {
        switch type {
        case .error: return .red
        case .warning: return .orange
        case .note: return .blue
        }
    }
}

#Preview {
    XcodeBuildLogPopover(
        log: """
        /path/to/File.swift:123:45: error: Cannot find 'foo' in scope
            let x = foo
                    ^~~
        /path/to/Other.swift:50:10: warning: Unused variable 'bar'
            let bar = 123
                ^~~
        ** BUILD FAILED **
        """,
        duration: 12.5,
        worktree: nil,
        onRetry: { print("Retry tapped") },
        onDismiss: { print("Dismiss tapped") }
    )
}
