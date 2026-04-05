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

    @Environment(\.controlActiveState) var controlActiveState
    @State var isHovered: Bool = false

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
        .background(backgroundFill)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
