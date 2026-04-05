import SwiftUI

private struct GitPanelRuntimeVisibilityKey: Equatable {
    let selectedTab: GitPanelTab
    let selectedHistoryCommitID: String?
}

extension GitPanelWindowContent {
    private var repositoryState: GitRepositoryState {
        gitSummaryStore.repositoryState
    }

    var shouldShowInitializeGitView: Bool {
        repositoryState == .notRepository
    }

    var effectiveThemeName: String {
        guard usePerAppearanceTheme else { return terminalThemeName }
        return AppearanceSettings.effectiveThemeName(colorScheme: colorScheme)
    }

    fileprivate var runtimeVisibilityKey: GitPanelRuntimeVisibilityKey {
        GitPanelRuntimeVisibilityKey(
            selectedTab: selectedTab,
            selectedHistoryCommitID: selectedHistoryCommit?.id
        )
    }

    var surfaceColor: Color {
        Color(nsColor: GhosttyThemeParser.loadBackgroundColor(named: effectiveThemeName))
    }

    var body: some View {
        Group {
            if shouldShowInitializeGitView {
                initializeGitView
            } else if selectedTab == .prs {
                PullRequestsView(repoPath: worktreePath)
            } else {
                HStack(spacing: 0) {
                    leftPanel
                        .frame(width: leftPanelWidth)

                    resizableDivider

                    rightPanel
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(surfaceColor)
        .toolbarBackground(surfaceColor, for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        .onAppear {
            syncRuntimeVisibility()
            reviewManager.load(for: worktreePath)
            _ = updateChangedFilesCache()
        }
        .onDisappear {
            runtime.setGitPanelVisible(false, showsWorkingDiff: false, showsWorkflow: false)
        }
        .task(id: gitStatus) {
            let changed = updateChangedFilesCache()
            guard changed, selectedHistoryCommit != nil else { return }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await synchronizeDiffOutput(for: selectedHistoryCommit)
        }
        .task(id: selectedHistoryCommit?.id) {
            await synchronizeDiffOutput(for: selectedHistoryCommit)
        }
        .task(id: runtimeVisibilityKey) {
            syncRuntimeVisibility()
        }
        .sheet(item: $commentPopoverLine) { line in
            CommentPopover(
                diffLine: line,
                filePath: commentPopoverFilePath ?? "",
                existingComment: reviewManager.comments.first {
                    $0.filePath == commentPopoverFilePath && $0.lineNumber == line.lineNumber
                },
                onSave: { text in
                    if let existing = reviewManager.comments.first(where: {
                        $0.filePath == commentPopoverFilePath && $0.lineNumber == line.lineNumber
                    }) {
                        reviewManager.updateComment(id: existing.id, comment: text)
                    } else {
                        reviewManager.addComment(for: line, filePath: commentPopoverFilePath ?? "", comment: text)
                    }
                    commentPopoverLine = nil
                },
                onCancel: {
                    commentPopoverLine = nil
                },
                onDelete: reviewManager.comments.first(where: {
                    $0.filePath == commentPopoverFilePath && $0.lineNumber == line.lineNumber
                }).map { existing in
                    {
                        reviewManager.deleteComment(id: existing.id)
                        commentPopoverLine = nil
                    }
                }
            )
        }
        .sheet(isPresented: $showAgentPicker) {
            SendToAgentSheet(
                worktree: worktree,
                commentsMarkdown: reviewManager.exportToMarkdown(),
                onDismiss: {
                    showAgentPicker = false
                },
                onSend: {
                    reviewManager.clearAll()
                    onClose()
                }
            )
        }
        .sheet(item: $selectedWorkflowForTrigger) { workflow in
            WorkflowTriggerFormView(
                workflow: workflow,
                currentBranch: gitStatus.currentBranch.isEmpty ? "main" : gitStatus.currentBranch,
                service: workflowService,
                onDismiss: {
                    selectedWorkflowForTrigger = nil
                }
            )
        }
    }

    var resizableDivider: some View {
        GitResizableDivider { value in
            let newWidth = leftPanelWidth + value.translation.width
            leftPanelWidth = min(max(newWidth, minLeftPanelWidth), maxLeftPanelWidth)
        }
    }
}
