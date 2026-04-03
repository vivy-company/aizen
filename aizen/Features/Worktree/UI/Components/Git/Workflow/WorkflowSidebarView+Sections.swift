import SwiftUI

extension WorkflowSidebarView {
    var workflowsSection: some View {
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

    var runsSection: some View {
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
}
