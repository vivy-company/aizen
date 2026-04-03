//
//  RunSidebarRow.swift
//  aizen
//
//  Row view for individual workflow run items in the workflow sidebar
//

import SwiftUI

struct RunSidebarRow: View {
    let run: WorkflowRun
    let isSelected: Bool
    let onSelect: () -> Void
    let onCancel: () -> Void

    @Environment(\.controlActiveState) private var controlActiveState
    @State private var isHovered: Bool = false

    private var selectedHighlightColor: Color {
        controlActiveState == .key ? Color(nsColor: .systemRed) : Color(nsColor: .systemRed).opacity(0.78)
    }

    private var selectionFillColor: Color {
        let base = NSColor.unemphasizedSelectedContentBackgroundColor
        let alpha: Double = controlActiveState == .key ? 0.26 : 0.18
        return Color(nsColor: base).opacity(alpha)
    }

    private var shortCommit: String {
        String(run.commit.prefix(7))
    }

    private var relativeTimestamp: String? {
        if let startedAt = run.startedAt {
            return RelativeDateFormatter.shared.string(from: startedAt)
        }
        if let completedAt = run.completedAt {
            return RelativeDateFormatter.shared.string(from: completedAt)
        }
        return nil
    }

    private var statusColor: Color {
        if let conclusion = run.conclusion {
            switch conclusion {
            case .success: return .green
            case .failure, .timedOut, .actionRequired: return .red
            case .cancelled: return .secondary
            case .skipped, .neutral: return .secondary
            }
        }

        switch run.status {
        case .inProgress, .queued, .pending, .waiting:
            return .orange
        default:
            return .secondary
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            WorkflowRunStatusIconView(
                run: run,
                iconSize: 12,
                progressFrame: 14,
                progressStyle: .mini,
                colorOverride: isSelected ? selectedHighlightColor : nil
            )
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(run.workflowName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isSelected ? selectedHighlightColor : .primary)
                        .lineLimit(1)

                    Spacer()

                    if let timestamp = relativeTimestamp {
                        Text(timestamp)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.secondary.opacity(0.75))
                    }
                }

                HStack(spacing: 8) {
                    Text("#\(run.runNumber)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Text("•")
                        .foregroundStyle(Color.secondary.opacity(0.45))

                    Text(shortCommit)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)

                    if !run.branch.isEmpty {
                        Text("•")
                            .foregroundStyle(Color.secondary.opacity(0.45))

                        Text(run.branch)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Text("•")
                        .foregroundStyle(Color.secondary.opacity(0.45))

                    Text(run.displayStatus)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(statusColor)
                }
            }

            Spacer(minLength: 8)

            if run.isInProgress && isHovered {
                Button {
                    onCancel()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                        .frame(width: 22, height: 22)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.10))
                        )
                }
                .buttonStyle(.plain)
                .help(String(localized: "git.workflow.cancelRun"))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Group {
                if isSelected {
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(selectionFillColor)
                } else if isHovered {
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white.opacity(0.06))
                } else {
                    Color.clear
                }
            }
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
