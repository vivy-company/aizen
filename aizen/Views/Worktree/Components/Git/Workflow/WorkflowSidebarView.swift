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

    var body: some View {
        VStack(spacing: 0) {
            // Header
            sidebarHeader

            Divider()

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
                    VStack(alignment: .leading, spacing: 16) {
                        workflowsSection
                        runsSection
                    }
                    .padding()
                }
            }

            // Error banner
            if let error = service.error {
                errorBanner(error)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Header

    private var sidebarHeader: some View {
        HStack {
            Image(systemName: service.provider == .github ? "bolt.circle.fill" : "gearshape.2.fill")
                .foregroundStyle(.secondary)

            Text(service.provider.displayName)
                .font(.subheadline)
                .fontWeight(.semibold)

            Spacer()

            if service.isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            Button {
                Task {
                    await service.refresh()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help(String(localized: "general.refresh"))
        }
        .frame(height: 44)
        .padding(.horizontal, 12)
    }

    // MARK: - Workflows Section

    private var workflowsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "git.workflow.title"))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

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

    // MARK: - Runs Section

    private var runsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "git.workflow.recentRuns"))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

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

    @State private var isHovered: Bool = false
    @State private var isButtonHovered: Bool = false
    @State private var isButtonPressed: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            // Workflow info (two lines) - clickable area
            VStack(alignment: .leading, spacing: 2) {
                Text(workflow.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                Text(workflow.path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                onSelect()
            }

            // Trigger button
            if workflow.canTrigger {
                ZStack {
                    Circle()
                        .fill(.clear)
                        .frame(width: 32, height: 32)

                    Image(systemName: "play.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isButtonHovered ? .white : .secondary)
                }
                .background {
                    glassPlayButtonBackground
                }
                .scaleEffect(isButtonPressed ? 0.92 : (isButtonHovered ? 1.05 : 1.0))
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isButtonHovered)
                .animation(.spring(response: 0.2, dampingFraction: 0.5), value: isButtonPressed)
                .onHover { hovering in
                    isButtonHovered = hovering
                }
                .onTapGesture {
                    onTrigger(workflow)
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in isButtonPressed = true }
                        .onEnded { _ in isButtonPressed = false }
                )
                .help(String(localized: "git.workflow.run"))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            glassRowBackground
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    @ViewBuilder
    private var glassRowBackground: some View {
        if #available(macOS 26.0, *) {
            RoundedRectangle(cornerRadius: 12)
                .fill(.clear)
                .glassEffect(
                    isSelected ? .regular.tint(.accentColor.opacity(0.3)) : .regular,
                    in: RoundedRectangle(cornerRadius: 12)
                )
                .opacity(isSelected ? 1 : (isHovered ? 0.9 : 0.7))
        } else {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: isSelected ? .selectedContentBackgroundColor : .controlBackgroundColor))
                .opacity(isSelected ? 1 : (isHovered ? 0.9 : 0.7))
        }
    }

    @ViewBuilder
    private var glassPlayButtonBackground: some View {
        if #available(macOS 26.0, *) {
            Circle()
                .fill(.clear)
                .frame(width: 32, height: 32)
                .glassEffect(
                    isButtonHovered ? .regular.tint(.accentColor) : .regular,
                    in: Circle()
                )
        } else {
            Circle()
                .fill(isButtonHovered ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                .frame(width: 32, height: 32)
                .overlay(
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
                )
        }
    }
}

// MARK: - Run Row

struct RunSidebarRow: View {
    let run: WorkflowRun
    let isSelected: Bool
    let onSelect: () -> Void
    let onCancel: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            // Status icon
            WorkflowRunStatusIconView(
                run: run,
                iconSize: 12,
                progressFrame: 14,
                progressStyle: .mini
            )
                .frame(width: 14)

            // Run info
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text("#\(run.runNumber)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))

                    Text(run.workflowName)
                        .font(.system(size: 11))
                        .lineLimit(1)
                }

                HStack(spacing: 4) {
                    Text(run.commit)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)

                    if let startedAt = run.startedAt {
                        Text(WorkflowRelativeTimeFormatter.string(from: startedAt))
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            // Cancel button
            if run.isInProgress && isHovered {
                Button {
                    onCancel()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .help(String(localized: "git.workflow.cancelRun"))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .modifier(SelectableRowModifier(isSelected: isSelected, isHovered: isHovered))
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

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.clear)
                            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 6))
                    } else if isHovered {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.clear)
                            .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 6))
                    }
                }
        } else {
            content
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? Color(nsColor: .selectedContentBackgroundColor) : (isHovered ? Color(nsColor: .unemphasizedSelectedContentBackgroundColor) : Color.clear))
                )
        }
    }
}
