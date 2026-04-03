//
//  WorkflowRunDetailView.swift
//  aizen
//
//  Displays workflow run details including jobs, steps, and logs
//

import SwiftUI

struct WorkflowRunDetailView: View {
    @ObservedObject var service: WorkflowService

    @State var selectedJobId: String?
    @State private var selectedRunId: String?
    @State private var showCancelConfirmation: Bool = false

    @AppStorage("editorFontFamily") private var editorFontFamily: String = "Menlo"

    var run: WorkflowRun? { service.selectedRun }
    var jobs: [WorkflowJob] { service.selectedRunJobs }

    private struct SelectionSyncKey: Hashable {
        let runId: String
        let jobs: [WorkflowJob]
    }

    var body: some View {
        if let run = run {
            VStack(spacing: 0) {
                // Run header
                runHeader(run)

                GitWindowDivider()

                // Jobs and logs
            HSplitView {
                // Jobs panel
                jobsPanel
                    .frame(minWidth: 200, idealWidth: 250, maxWidth: 350)

                    // Logs panel
                    logsPanel
                }
            }
            .task(id: SelectionSyncKey(runId: run.id, jobs: jobs)) {
                syncSelectedJob(for: run, jobs: jobs)
            }
        } else {
            Text("No run selected")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Header

    private func runHeader(_ run: WorkflowRun) -> some View {
        HStack(spacing: 12) {
            // Status
            statusBadge(run)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(run.workflowName)
                        .font(.system(size: 13, weight: .semibold))

                    Text("#\(run.runNumber)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Label(run.branch, systemImage: "arrow.triangle.branch")
                    Label(run.commit, systemImage: "number")
                    Label(run.event, systemImage: "bolt")
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }

            Spacer()

            // Actions
            if run.isInProgress {
                Button {
                    showCancelConfirmation = true
                } label: {
                    Label("Cancel", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .controlSize(.small)
                .confirmationDialog(
                    "Cancel Workflow Run?",
                    isPresented: $showCancelConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Cancel Run", role: .destructive) {
                        Task {
                            _ = await service.cancelRun(run)
                        }
                    }
                    Button("Keep Running", role: .cancel) {}
                } message: {
                    Text("This will stop the workflow run #\(run.runNumber). This action cannot be undone.")
                }
            }

            if let url = run.url, let urlObj = URL(string: url) {
                Link(destination: urlObj) {
                    Image(systemName: "arrow.up.right.square")
                }
                .buttonStyle(.borderless)
                .help("Open in browser")
            }
        }
        .frame(height: 44)
        .padding(.horizontal, 12)
    }

    private func statusBadge(_ run: WorkflowRun) -> some View {
        HStack(spacing: 4) {
            WorkflowRunStatusIconView(
                run: run,
                iconSize: 11,
                progressFrame: 12,
                progressStyle: .mini
            )

            Text(run.displayStatus)
                .font(.system(size: 11, weight: .semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .foregroundStyle(.white)
        .background(statusBackgroundColor(run))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func statusBackgroundColor(_ run: WorkflowRun) -> Color {
        WorkflowStatusIcon.badgeBackgroundColor(status: run.status, conclusion: run.conclusion)
    }

    private func syncSelectedJob(for run: WorkflowRun, jobs: [WorkflowJob]) {
        if selectedRunId != run.id {
            selectedRunId = run.id
            selectedJobId = nil
        } else if let selectedJobId, !jobs.contains(where: { $0.id == selectedJobId }) {
            self.selectedJobId = nil
        }

        if selectedJobId == nil && !jobs.isEmpty {
            selectedJobId = jobs.first(where: { $0.conclusion == .failure })?.id ?? jobs.first?.id
        }
    }

    // MARK: - Jobs Panel

    private var jobsPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Jobs")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    Task {
                        await service.refresh()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh")
            }
            .frame(height: 32)
            .padding(.horizontal, 12)

            GitWindowDivider()

            if jobs.isEmpty {
                VStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading jobs...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(jobs) { job in
                            JobRow(
                                job: job,
                                isSelected: selectedJobId == job.id,
                                onSelect: {
                                    selectedJobId = job.id
                                    Task {
                                        await service.loadLogs(runId: run?.id ?? "", jobId: job.id)
                                    }
                                }
                            )
                        }
                    }
                }
            }
        }
    }

}

// MARK: - Job Row

struct JobRow: View {
    let job: WorkflowJob
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isExpanded: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Job header
            Button(action: onSelect) {
                HStack(spacing: 8) {
                    // Expand/collapse for steps
                    if !job.steps.isEmpty {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isExpanded.toggle()
                            }
                        } label: {
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .frame(width: 12)
                    } else {
                        Spacer()
                            .frame(width: 12)
                    }

                    // Status icon
                    jobStatusIcon

                    // Job name
                    Text(job.name)
                        .font(.system(size: 12))
                        .lineLimit(1)

                    Spacer()

                    // Duration
                    if !job.durationString.isEmpty {
                        Text(job.durationString)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .modifier(JobRowSelectionModifier(isSelected: isSelected))
            }
            .buttonStyle(.plain)

            // Steps
            if isExpanded && !job.steps.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(job.steps) { step in
                        StepRow(step: step)
                    }
                }
                .padding(.leading, 32)
            }
        }
    }

    @ViewBuilder
    private var jobStatusIcon: some View {
        if job.status == .inProgress {
            ProgressView()
                .controlSize(.mini)
                .frame(width: 14, height: 14)
        } else {
            Image(systemName: WorkflowStatusIcon.iconName(status: job.status, conclusion: job.conclusion, fillStyle: .fill))
                .font(.system(size: 12))
                .foregroundStyle(WorkflowStatusIcon.color(status: job.status, conclusion: job.conclusion))
        }
    }
}

// MARK: - Step Row

struct StepRow: View {
    let step: WorkflowStep

    var body: some View {
        HStack(spacing: 6) {
            // Connector line
            Rectangle()
                .fill(GitWindowDividerStyle.color(opacity: 1))
                .frame(width: 1)
                .padding(.vertical, 2)

            // Status icon
            stepStatusIcon
                .frame(width: 12)

            // Step name
            Text(step.name)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()
        }
        .padding(.vertical, 3)
        .padding(.trailing, 12)
    }

    @ViewBuilder
    private var stepStatusIcon: some View {
        if step.status == .inProgress {
            ProgressView()
                .controlSize(.mini)
                .frame(width: 10, height: 10)
        } else {
            Image(systemName: WorkflowStatusIcon.iconName(status: step.status, conclusion: step.conclusion, fillStyle: .outline))
                .font(.system(size: 9))
                .foregroundStyle(WorkflowStatusIcon.color(status: step.status, conclusion: step.conclusion))
        }
    }
}

struct JobRowSelectionModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let isSelected: Bool

    func body(content: Content) -> some View {
        content
            .background(isSelected ? (colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05)) : Color.clear)
    }
}
