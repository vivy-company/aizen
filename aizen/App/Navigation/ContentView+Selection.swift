//
//  ContentView+Selection.swift
//  aizen
//
//  Created by Codex on 2026-04-03.
//

import CoreData

extension ContentView {
    func navigateToWorktree(workspaceId: UUID, repoId: UUID, worktreeId: UUID) {
        guard let workspace = workspaceGraphQueryController.workspace(id: workspaceId) else {
            return
        }

        selectWorkspace(workspace, preserveSelection: true)

        let allRepositories = workspaceGraphQueryController.repositories(in: workspace)
        let allWorkspaceWorktrees = allRepositories.flatMap { repository in
            workspaceGraphQueryController.worktrees(in: repository)
        }

        if let targetWorktree = allWorkspaceWorktrees.first(where: { $0.id == worktreeId }),
           let targetRepository = targetWorktree.repository {
            if isCrossProjectRepository(targetRepository) {
                setCrossProjectSelected(true, preferredWorktree: targetWorktree)
                return
            }

            selectRepository(targetRepository)
            selectWorktree(targetWorktree)
            return
        }

        if let crossProjectRepository = allRepositories.first(where: { $0.id == repoId && isCrossProjectRepository($0) }) {
            let worktrees = workspaceGraphQueryController.worktrees(in: crossProjectRepository)
            if let worktree = worktrees.first(where: { $0.id == worktreeId }) {
                setCrossProjectSelected(true, preferredWorktree: worktree)
            } else {
                setCrossProjectSelected(true)
            }
            return
        }

        let repositories = visibleRepositories(in: workspace)
        if let repository = repositories.first(where: { $0.id == repoId }) {
            selectRepository(repository)
            let worktrees = workspaceGraphQueryController.worktrees(in: repository)
            if let worktree = worktrees.first(where: { $0.id == worktreeId }) {
                selectWorktree(worktree)
            }
        }
    }

    func selectWorkspace(_ workspace: Workspace?, preserveSelection: Bool = false) {
        selectionStore.selectedWorkspace = workspace
        selectedWorkspaceId = workspace?.id?.uuidString

        if preserveSelection {
            return
        }

        if selectionStore.suppressWorkspaceAutoSelection {
            selectionStore.suppressWorkspaceAutoSelection = false
            return
        }

        if selectionStore.isCrossProjectSelected {
            setCrossProjectSelected(false)
        }

        guard let workspace else {
            selectRepository(nil)
            return
        }

        let repositories = visibleRepositories(in: workspace)
        if let lastRepoId = workspace.lastSelectedRepositoryId,
           let lastRepo = repositories.first(where: { $0.id == lastRepoId }) {
            selectRepository(lastRepo)
        } else {
            selectRepository(repositories.first)
        }
    }

    func selectRepository(_ repository: Repository?) {
        selectionStore.selectedRepository = repository
        selectedRepositoryId = repository?.id?.uuidString

        guard let repository else {
            selectWorktree(nil)
            return
        }

        if isCrossProjectRepository(repository) {
            selectionStore.selectedRepository = nil
            selectedRepositoryId = nil
            setCrossProjectSelected(true)
            return
        }

        if repository.isDeleted || repository.isFault {
            selectionStore.selectedRepository = nil
            selectedRepositoryId = nil
            selectWorktree(nil)
            return
        }

        if selectionStore.isCrossProjectSelected {
            setCrossProjectSelected(false)
        }

        if let workspace = selectionStore.selectedWorkspace {
            workspace.lastSelectedRepositoryId = repository.id
            saveTask?.cancel()
            saveTask = Task {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                try? viewContext.save()
            }
        }

        let worktrees = workspaceGraphQueryController.worktrees(in: repository)
        if let restoredWorktreeId = getStoredWorktreeId(for: repository),
           let restoredWorktree = worktrees.first(where: { $0.id == restoredWorktreeId }) {
            selectWorktree(restoredWorktree)
            return
        }

        if let worktreeId = selectedWorktreeId,
           let uuid = UUID(uuidString: worktreeId),
           let restoredWorktree = worktrees.first(where: { $0.id == uuid }) {
            selectWorktree(restoredWorktree)
            return
        }

        let candidates = worktrees
        selectWorktree(candidates.first(where: { $0.isPrimary }) ?? candidates.first)
    }

    func selectWorktree(_ worktree: Worktree?) {
        if let worktree, worktree.isDeleted {
            selectionStore.selectedWorktree = nil
            selectedWorktreeId = nil
            if let repository = selectionStore.selectedRepository {
                let worktrees = workspaceGraphQueryController.worktrees(in: repository)
                let fallback = worktrees.first(where: { $0.isPrimary })
                if let fallback {
                    selectWorktree(fallback)
                }
            }
            return
        }

        selectionStore.selectedWorktree = worktree
        selectedWorktreeId = worktree?.id?.uuidString

        guard let worktree else { return }

        recordWorktreeInMRU(worktree)
        if let repository = selectionStore.selectedRepository {
            storeWorktreeSelection(worktree.id, for: repository)
        }
        Task { @MainActor in
            try? repositoryManager.updateWorktreeAccess(worktree)
        }
    }

}
