import SwiftUI

extension GitPanelWindowContent {
    @ViewBuilder
    var leftPanel: some View {
        switch selectedTab {
        case .git:
            gitTabContent
        case .history:
            GitHistoryView(
                worktreePath: worktreePath,
                selectedCommit: selectedHistoryCommit,
                onSelectCommit: { commit in
                    selectedHistoryCommit = commit
                }
            )
        case .comments:
            ReviewCommentsPanel(
                reviewManager: reviewManager,
                onScrollToLine: { filePath, _ in
                    scrollToFile = filePath
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        scrollToFile = nil
                    }
                },
                onCopyAll: {
                    let markdown = reviewManager.exportToMarkdown()
                    Clipboard.copy(markdown)
                },
                onSendToAgent: {
                    showAgentPicker = true
                }
            )
        case .workflows:
            WorkflowSidebarView(
                service: workflowService,
                onSelect: { workflow in
                    workflowService.selectedWorkflow = workflow
                    workflowService.selectedRun = nil
                },
                onTrigger: { workflow in
                    selectedWorkflowForTrigger = workflow
                }
            )
        case .prs:
            EmptyView()
        }
    }

    var gitTabContent: some View {
        GitSidebarView(
            worktreePath: worktreePath,
            onClose: onClose,
            gitStatus: gitStatus,
            isOperationPending: gitOperationService.isOperationPending,
            selectedDiffFile: visibleFile,
            onStageFile: { file in
                gitOperations.stageFile(file)
            },
            onUnstageFile: { file in
                gitOperations.unstageFile(file)
            },
            onStageAll: { completion in
                gitOperations.stageAll {
                    completion()
                }
            },
            onUnstageAll: {
                gitOperations.unstageAll()
            },
            onDiscardAll: {
                gitOperations.discardAll()
            },
            onCleanUntracked: {
                gitOperations.cleanUntracked()
            },
            onCommit: { message in
                gitOperations.commit(message)
            },
            onAmendCommit: { message in
                gitOperations.amendCommit(message)
            },
            onCommitWithSignoff: { message in
                gitOperations.commitWithSignoff(message)
            },
            onFileClick: { file in
                visibleFile = file
                scrollToFile = file
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    scrollToFile = nil
                }
            }
        )
    }
}
