//
//  TurnSummaryView.swift
//  aizen
//
//  Summary view shown at the end of a completed agent turn
//

import SwiftUI

struct TurnSummaryView: View {
    let summary: TurnSummary
    var onOpenInEditor: ((String) -> Void)?

    var body: some View {
        HStack(spacing: 6) {
            // Checkmark icon
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 10))
                .foregroundColor(.green)

            // Tool call count
            Text("\(summary.toolCallCount) tool call\(summary.toolCallCount == 1 ? "" : "s")")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            Text("·")
                .foregroundStyle(.tertiary)

            // Duration
            Text(summary.formattedDuration)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            // File change chips
            if !summary.fileChanges.isEmpty {
                Text("·")
                    .foregroundStyle(.tertiary)

                ForEach(summary.fileChanges.prefix(3)) { change in
                    TurnFileChip(change: change, onOpenInEditor: onOpenInEditor)
                }

                if summary.fileChanges.count > 3 {
                    Text("+\(summary.fileChanges.count - 3)")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

// MARK: - Turn File Chip (Compact)

struct TurnFileChip: View {
    let change: FileChangeSummary
    var onOpenInEditor: ((String) -> Void)?

    var body: some View {
        Button {
            onOpenInEditor?(change.path)
        } label: {
            HStack(spacing: 3) {
                // Filename
                Text(change.filename)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                // Line changes
                if change.linesAdded > 0 || change.linesRemoved > 0 {
                    HStack(spacing: 1) {
                        if change.linesAdded > 0 {
                            Text("+\(change.linesAdded)")
                                .foregroundColor(.green)
                        }
                        if change.linesRemoved > 0 {
                            Text("-\(change.linesRemoved)")
                                .foregroundColor(.red)
                        }
                    }
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(0.04))
            )
        }
        .buttonStyle(.plain)
    }
}
