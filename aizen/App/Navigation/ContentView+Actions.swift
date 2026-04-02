//
//  ContentView+Actions.swift
//  aizen
//
//  Created by Codex on 2026-04-03.
//

extension ContentView {
    fileprivate func isCrossProjectRepository(_ repository: Repository) -> Bool {
        repository.isCrossProject || repository.note == crossProjectRepositoryMarker
    }

    fileprivate func visibleRepositories(in workspace: Workspace) -> [Repository] {
        let repositories = (workspace.repositories as? Set<Repository>) ?? []
        return repositories
            .filter { !$0.isDeleted && !isCrossProjectRepository($0) }
            .sorted { ($0.name ?? "") < ($1.name ?? "") }
    }

    private func ensureCrossProjectWorktree(for workspace: Workspace) throws -> Worktree {
        try CrossProjectWorkspaceCoordinator(
            viewContext: viewContext,
            repositoryMarker: crossProjectRepositoryMarker
        )
        .ensureWorktree(
            for: workspace,
            visibleRepositories: visibleRepositories(in: workspace)
        )
    }

    fileprivate func prepareCrossProjectWorkspaceIfNeeded() {
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

    fileprivate func presentCrossProjectOnboardingIfNeeded() {
        guard !hasShownCrossProjectOnboarding else {
            return
        }

        hasShownCrossProjectOnboarding = true
        showingCrossProjectOnboarding = true
    }

    private func showCommandPalette() {
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

    fileprivate func currentActiveWorktree() -> Worktree? {
        if selectionStore.isCrossProjectSelected {
            return selectionStore.crossProjectWorktree
        }
        return selectionStore.selectedWorktree
    }
}
