//
//  WorkflowSidebarView.swift
//  aizen
//
//  Sidebar view for workflow list and runs selection
//

import SwiftUI

struct WorkflowSidebarView: View {
    @ObservedObject var service: WorkflowService
    let onSelect: (Workflow) -> Void
    let onTrigger: (Workflow) -> Void

    var totalItemsCount: Int {
        service.workflows.count + service.runs.count
    }

    var body: some View {
        VStack(spacing: 0) {
            sidebarHeader
            GitWindowDivider()

            if service.isInitializing {
                initializingView
            } else if !service.isConfigured {
                noProviderView
            } else if !service.isCLIInstalled {
                cliNotInstalledView
            } else if !service.isAuthenticated {
                notAuthenticatedView
            } else {
                // Content
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        workflowsSection
                        runsSection
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                }
            }
            if let error = service.error {
                errorBanner(error)
            }
        }
    }
}

// MARK: - Run Row

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

// MARK: - Selectable Row Modifier with Liquid Glass

struct SelectableRowModifier: ViewModifier {
    let isSelected: Bool
    let isHovered: Bool
    var showsIdleBackground: Bool = true
    var cornerRadius: CGFloat = 8

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if #available(macOS 26.0, *) {
            content
                .background {
                    if isSelected {
                        GlassEffectContainer {
                            shape
                                .fill(.white.opacity(0.001))
                                .glassEffect(.regular.tint(.accentColor.opacity(0.24)).interactive(), in: shape)
                            shape
                                .fill(Color.accentColor.opacity(0.10))
                        }
                    } else if isHovered {
                        shape
                            .fill(Color.white.opacity(0.05))
                    } else if showsIdleBackground {
                        shape
                            .fill(Color.white.opacity(0.02))
                    }
                }
        } else {
            content
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            isSelected
                                ? Color(nsColor: .selectedContentBackgroundColor)
                                : (isHovered ? Color.white.opacity(0.06) : (showsIdleBackground ? Color.white.opacity(0.02) : .clear))
                        )
                )
        }
    }
}
