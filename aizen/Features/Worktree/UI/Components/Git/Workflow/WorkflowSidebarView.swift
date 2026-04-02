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

    private var totalItemsCount: Int {
        service.workflows.count + service.runs.count
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
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

            // Error banner
            if let error = service.error {
                errorBanner(error)
            }
        }
    }

    // MARK: - Header

    private var sidebarHeader: some View {
        HStack(spacing: 12) {
            Text(service.provider.displayName)
                .font(.headline)

            if totalItemsCount > 0 {
                TagBadge(text: "\(totalItemsCount)", color: .secondary, cornerRadius: 6)
            }

            Spacer()

            if service.isLoading {
                ProgressView()
                    .controlSize(.mini)
            }

            Button {
                Task {
                    await service.refresh()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .background(chipBackground)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(service.isLoading)
            .help(String(localized: "general.refresh"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var chipBackground: some ShapeStyle {
        Color.white.opacity(0.08)
    }

    // MARK: - Workflows Section

    private var workflowsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(localized: "git.workflow.title"))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)

            if service.isLoading && service.workflows.isEmpty {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                    Text(String(localized: "general.loading"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
            } else if service.workflows.isEmpty {
                HStack {
                    Image(systemName: "doc.badge.gearshape")
                        .foregroundStyle(.tertiary)
                    Text(String(localized: "git.workflow.noWorkflows"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(service.workflows) { workflow in
                        WorkflowSidebarRow(
                            workflow: workflow,
                            isSelected: service.selectedWorkflow?.id == workflow.id,
                            onSelect: { onSelect(workflow) },
                            onTrigger: onTrigger
                        )
                    }
                }
            }
        }
    }

    // MARK: - Runs Section

    private var runsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(localized: "git.workflow.recentRuns"))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)

            if service.isLoading && service.runs.isEmpty {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                    Text(String(localized: "general.loading"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
            } else if service.runs.isEmpty {
                HStack {
                    Image(systemName: "clock.badge.questionmark")
                        .foregroundStyle(.tertiary)
                    Text(String(localized: "git.workflow.noRuns"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(service.runs) { run in
                        RunSidebarRow(
                            run: run,
                            isSelected: service.selectedRun?.id == run.id,
                            onSelect: {
                                Task {
                                    await service.selectRun(run)
                                }
                            },
                            onCancel: {
                                Task {
                                    _ = await service.cancelRun(run)
                                }
                            }
                        )
                    }
                }
            }
        }
    }

    // MARK: - Empty States

    private var initializingView: some View {
        VStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(String(localized: "git.workflow.checkingCLI"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noProviderView: some View {
        VStack(spacing: 12) {
            Image(systemName: "bolt.slash")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)

            Text(String(localized: "git.workflow.noProvider"))
                .font(.subheadline)
                .fontWeight(.medium)

            Text(String(localized: "git.workflow.addFiles"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var cliNotInstalledView: some View {
        VStack(spacing: 12) {
            Image(systemName: "terminal")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)

            Text(String(localized: "git.workflow.cliNotInstalled \(service.provider.cliCommand)"))
                .font(.subheadline)
                .fontWeight(.medium)

            CodePill(
                text: "brew install \(service.provider.cliCommand)",
                backgroundColor: Color(nsColor: .controlBackgroundColor),
                horizontalPadding: 6,
                verticalPadding: 6
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var notAuthenticatedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.badge.key")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)

            Text(String(localized: "git.workflow.notAuthenticated"))
                .font(.subheadline)
                .fontWeight(.medium)

            CodePill(
                text: "\(service.provider.cliCommand) auth login",
                backgroundColor: Color(nsColor: .controlBackgroundColor),
                horizontalPadding: 6,
                verticalPadding: 6
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func errorBanner(_ error: WorkflowError) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .font(.caption)

            Text(error.localizedDescription)
                .font(.caption2)
                .lineLimit(2)

            Spacer()

            Button {
                service.error = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
            }
            .buttonStyle(.borderless)
        }
        .padding(6)
        .background(Color.yellow.opacity(0.1))
    }
}

// MARK: - Workflow Row

struct WorkflowSidebarRow: View {
    let workflow: Workflow
    let isSelected: Bool
    let onSelect: () -> Void
    let onTrigger: (Workflow) -> Void

    @Environment(\.controlActiveState) private var controlActiveState
    @State private var isHovered: Bool = false
    @State private var isButtonHovered: Bool = false

    private var selectedHighlightColor: Color {
        controlActiveState == .key ? Color(nsColor: .systemRed) : Color(nsColor: .systemRed).opacity(0.78)
    }

    private var selectionFillColor: Color {
        let base = NSColor.unemphasizedSelectedContentBackgroundColor
        let alpha: Double = controlActiveState == .key ? 0.26 : 0.18
        return Color(nsColor: base).opacity(alpha)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "bolt.horizontal.circle")
                .font(.system(size: 13))
                .foregroundStyle(isSelected ? selectedHighlightColor : .secondary)
                .frame(width: 22, alignment: .top)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(workflow.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isSelected ? selectedHighlightColor : .primary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer()

                    if workflow.state != .active {
                        Text(workflow.state.rawValue)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 8) {
                    Text(workflow.path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if workflow.canTrigger {
                        Text("•")
                            .foregroundStyle(Color.secondary.opacity(0.45))

                        Text("manual")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .padding(.trailing, workflow.canTrigger ? 40 : 0)
        .overlay(alignment: .trailing) {
            if workflow.canTrigger {
                Button {
                    onTrigger(workflow)
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isButtonHovered ? .white : .secondary)
                        .frame(width: 34, height: 34)
                        .background(
                            Circle()
                                .fill(isButtonHovered ? Color.accentColor : Color.white.opacity(0.05))
                        )
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    isButtonHovered = hovering
                }
                .help(String(localized: "git.workflow.run"))
                .padding(.trailing, 10)
            }
        }
        .background(
            Group {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(selectionFillColor)
                } else if isHovered {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06))
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
