//
//  XcodeBuildLogPopover+Shell.swift
//  aizen
//

import SwiftUI

extension XcodeBuildLogPopover {
    var popoverContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            logContent

            Divider()

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
    var header: some View {
        HStack {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
            Text("Build Failed")
                .font(.headline)

            Spacer()

            if let duration = duration {
                Text(DurationFormatter.short(duration))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    @ViewBuilder
    var actionBar: some View {
        HStack(spacing: 12) {
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

            if worktree != nil {
                Button {
                    showingSendToAgent = true
                } label: {
                    Label("Send to Agent", systemImage: "paperplane")
                }
                .disabled(log.isEmpty)
            }

            Spacer()

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
}
