//
//  AppNavigationDetailColumn.swift
//  aizen
//
//  Created by Codex on 2026-04-03.
//

import SwiftUI

struct AppNavigationDetailColumn: View {
    @ObservedObject var selectionStore: AppNavigationSelectionStore
    let isCrossProjectSelected: Bool
    let crossProjectWorktree: Worktree?
    let selectedWorktree: Worktree?
    let repositoryManager: WorkspaceRepositoryStore
    let tabStateManager: WorktreeTabStateStore
    @Binding var gitChangesContext: GitChangesContext?
    let onSelectCrossProjectWorktree: (Worktree?) -> Void
    let onPrepareCrossProjectWorkspaceIfNeeded: () -> Void
    let onSelectWorktree: (Worktree?) -> Void

    var body: some View {
        if isCrossProjectSelected, let worktree = crossProjectWorktree, !worktree.isDeleted {
            WorktreeDetailView(
                worktree: worktree,
                repositoryManager: repositoryManager,
                navigationSelectionStore: selectionStore,
                tabStateManager: tabStateManager,
                gitChangesContext: $gitChangesContext,
                onWorktreeDeleted: { _ in
                    onSelectCrossProjectWorktree(nil)
                    onPrepareCrossProjectWorkspaceIfNeeded()
                },
                showZenModeButton: false
            )
            .id(worktree.id)
        } else if isCrossProjectSelected {
            Color.clear
                .task {
                    onPrepareCrossProjectWorkspaceIfNeeded()
                }
        } else if let worktree = selectedWorktree, !worktree.isDeleted {
            WorktreeDetailView(
                worktree: worktree,
                repositoryManager: repositoryManager,
                navigationSelectionStore: selectionStore,
                tabStateManager: tabStateManager,
                gitChangesContext: $gitChangesContext,
                onWorktreeDeleted: { nextWorktree in
                    onSelectWorktree(nextWorktree)
                },
                showZenModeButton: true
            )
            .id(worktree.id)
        } else {
            placeholderView(
                titleKey: "contentView.selectWorktree",
                systemImage: "arrow.triangle.branch",
                descriptionKey: "contentView.selectWorktreeDescription"
            )
        }
    }
}
