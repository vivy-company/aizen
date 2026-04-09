//
//  ContentView+CrossProject.swift
//  aizen
//
//  Created by Codex on 2026-04-03.
//

import CoreData
import Foundation

extension ContentView {
    func isCrossProjectRepository(_ repository: Repository) -> Bool {
        repository.isCrossProject || repository.note == crossProjectRepositoryMarker
    }

    func visibleRepositories(in workspace: Workspace) -> [Repository] {
        workspaceGraphQueryController.visibleRepositories(
            in: workspace,
            crossProjectMarker: crossProjectRepositoryMarker
        )
    }

    func ensureCrossProjectWorktree(for workspace: Workspace) throws -> Worktree {
        try CrossProjectWorkspaceCoordinator(
            viewContext: viewContext,
            repositoryMarker: crossProjectRepositoryMarker,
            workspaceGraphQueryController: workspaceGraphQueryController
        )
        .ensureWorktree(
            for: workspace,
            visibleRepositories: visibleRepositories(in: workspace)
        )
    }

    func prepareCrossProjectWorkspaceIfNeeded() {
        guard selectionStore.isCrossProjectSelected, let workspace = selectionStore.selectedWorkspace else {
            selectCrossProjectWorktree(nil)
            return
        }

        do {
            selectCrossProjectWorktree(try ensureCrossProjectWorktree(for: workspace))
        } catch {
            selectCrossProjectWorktree(nil)
        }
    }

    func presentCrossProjectOnboardingIfNeeded() {
        guard !hasShownCrossProjectOnboarding else {
            return
        }

        hasShownCrossProjectOnboarding = true
        showingCrossProjectOnboarding = true
    }

    func selectCrossProjectWorktree(_ worktree: Worktree?) {
        selectionStore.crossProjectWorktree = worktree
        guard selectionStore.isCrossProjectSelected, let worktree, !worktree.isDeleted else {
            return
        }
        recordWorktreeInMRU(worktree)
    }

    func setCrossProjectSelected(_ isSelected: Bool, preferredWorktree: Worktree? = nil) {
        if !isSelected {
            selectionStore.isCrossProjectSelected = false
            if let previousZenMode = selectionStore.zenModeBeforeCrossProjectSelection {
                zenModeEnabled = previousZenMode
                selectionStore.zenModeBeforeCrossProjectSelection = nil
            }
            selectCrossProjectWorktree(nil)
            return
        }

        if selectionStore.zenModeBeforeCrossProjectSelection == nil {
            selectionStore.zenModeBeforeCrossProjectSelection = zenModeEnabled
        }

        selectionStore.isCrossProjectSelected = true
        zenModeEnabled = true
        selectionStore.selectedRepository = nil
        selectedRepositoryId = nil
        selectionStore.selectedWorktree = nil
        selectedWorktreeId = nil

        if let preferredWorktree, !preferredWorktree.isDeleted {
            selectCrossProjectWorktree(preferredWorktree)
        } else {
            prepareCrossProjectWorkspaceIfNeeded()
        }

        presentCrossProjectOnboardingIfNeeded()
    }
}
