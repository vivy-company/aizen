import SwiftUI

extension WorkflowRunsListView {
    var loadingState: some View {
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

    var emptyState: some View {
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
                WorkflowRunStatusIconView(
                    run: run,
                    iconSize: 14,
                    progressFrame: 16,
                    progressStyle: .scaled(0.5)
                )
                .frame(width: 16)

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

                if let startedAt = run.startedAt {
                    Text(RelativeDateFormatter.shared.string(from: startedAt))
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }

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
