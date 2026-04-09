//
//  AppNavigationDetailColumn.swift
//  aizen
//
//  Created by Codex on 2026-04-03.
//

import SwiftUI

struct AppNavigationDetailColumn: View {
    @ObservedObject var selectionStore: AppNavigationSelectionStore
    @ObservedObject var sceneRegistry: WorktreeSceneRegistry
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
            cachedDetailHost(
                activeWorktree: worktree,
                showZenModeButton: false
            ) { _ in
                onSelectCrossProjectWorktree(nil)
                onPrepareCrossProjectWorkspaceIfNeeded()
            }
        } else if isCrossProjectSelected {
            Color.clear
                .task {
                    onPrepareCrossProjectWorkspaceIfNeeded()
                }
        } else if let worktree = selectedWorktree, !worktree.isDeleted {
            cachedDetailHost(
                activeWorktree: worktree,
                showZenModeButton: true
            ) { nextWorktree in
                onSelectWorktree(nextWorktree)
            }
        } else {
            placeholderView(
                titleKey: "contentView.selectWorktree",
                systemImage: "arrow.triangle.branch",
                descriptionKey: "contentView.selectWorktreeDescription"
            )
        }
    }

    @ViewBuilder
    private func cachedDetailHost(
        activeWorktree: Worktree,
        showZenModeButton: Bool,
        onWorktreeDeleted: @escaping (Worktree?) -> Void
    ) -> some View {
        if let scene = sceneRegistry.scene(for: activeWorktree) {
            WorktreeDetailView(
                scene: scene,
                navigationSelectionStore: selectionStore,
                gitChangesContext: $gitChangesContext,
                onWorktreeDeleted: onWorktreeDeleted,
                showZenModeButton: showZenModeButton,
                isActive: true
            )
        } else {
            Color.clear
        }
    }
}
