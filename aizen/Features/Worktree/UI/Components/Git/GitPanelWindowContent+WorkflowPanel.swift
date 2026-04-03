import SwiftUI

extension GitPanelWindowContent {
    @ViewBuilder
    var rightPanel: some View {
        switch selectedTab {
        case .prs:
            EmptyView()
        case .workflows:
            workflowDetailPanel
        default:
            diffPanel
        }
    }

    var workflowDetailPanel: some View {
        Group {
            if let workflow = workflowService.selectedWorkflow {
                WorkflowFileView(workflow: workflow, worktreePath: worktreePath)
                    .id(workflow.id)
            } else if workflowService.selectedRun != nil {
                WorkflowRunDetailView(service: workflowService)
            } else {
                workflowEmptyState
            }
        }
    }

    var workflowEmptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bolt.circle")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text(String(localized: "git.workflow.selectRun"))
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(String(localized: "git.workflow.selectRunHint"))
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
