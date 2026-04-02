//
//  ContentView+Actions.swift
//  aizen
//
//  Created by Codex on 2026-04-03.
//

import Foundation

extension ContentView {
    func showCommandPalette() {
        let activeWorktree = currentActiveWorktree()
        let currentRepositoryId = selectionStore.selectedRepository?.id?.uuidString
            ?? activeWorktree?.repository?.id?.uuidString
        let currentWorkspaceId = selectionStore.selectedWorkspace?.id?.uuidString
            ?? activeWorktree?.repository?.workspace?.id?.uuidString

        navigator.showCommandPalette(
            viewContext: viewContext,
            currentRepositoryId: currentRepositoryId,
            currentWorkspaceId: currentWorkspaceId,
            onNavigate: { action in
                navigator.handleCommandPaletteNavigation(action, navigateToWorktree: navigateToWorktree)
            }
        )
    }

    func currentActiveWorktree() -> Worktree? {
        if selectionStore.isCrossProjectSelected {
            return selectionStore.crossProjectWorktree
        }
        return selectionStore.selectedWorktree
    }
}
