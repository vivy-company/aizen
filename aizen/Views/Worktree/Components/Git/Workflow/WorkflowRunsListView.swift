//
//  WorkflowRunsListView.swift
//  aizen
//
//  Displays list of workflow runs for the current branch
//

import SwiftUI

struct WorkflowRunsListView: View {
    let runs: [WorkflowRun]
    let branch: String
    let isLoading: Bool
    let onSelectRun: (WorkflowRun) -> Void
    let onCancelRun: (WorkflowRun) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent Runs")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                Spacer()

                TagBadge(
                    text: branch,
                    color: Color(nsColor: .controlBackgroundColor),
                    font: .caption,
                    backgroundOpacity: 1,
                    textColor: .secondary
                )
            }

            if isLoading && runs.isEmpty {
                loadingState
            } else if runs.isEmpty {
                emptyState
            } else {
                ForEach(runs) { run in
                    WorkflowRunRow(
                        run: run,
                        onSelect: { onSelectRun(run) },
                        onCancel: { onCancelRun(run) }
                    )
                }
            }
        }
    }

    private var loadingState: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)

            Text("Loading runs...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 12)
    }

    private var emptyState: some View {
        HStack {
            Image(systemName: "clock.badge.questionmark")
                .foregroundStyle(.tertiary)

            Text("No runs found for this branch")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 12)
    }
}

struct WorkflowRunRow: View {
    let run: WorkflowRun
    let onSelect: () -> Void
    let onCancel: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                // Status icon
                WorkflowRunStatusIconView(
                    run: run,
                    iconSize: 14,
                    progressFrame: 16,
                    progressStyle: .scaled(0.5)
                )
                    .frame(width: 16)

                // Run info
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("#\(run.runNumber)")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))

                        Text(run.workflowName)
                            .font(.system(size: 12))
                            .lineLimit(1)
                    }

                    HStack(spacing: 6) {
                        if let message = run.commitMessage {
                            Text(message)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Text(run.commit)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                // Time
                if let startedAt = run.startedAt {
                    Text(RelativeDateFormatter.shared.string(from: startedAt))
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }

                // Cancel button for in-progress runs
                if run.isInProgress {
                    Button {
                        onCancel()
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                    .opacity(isHovered ? 1 : 0)
                    .help("Cancel run")
                }

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color(nsColor: .unemphasizedSelectedContentBackgroundColor) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }

}
