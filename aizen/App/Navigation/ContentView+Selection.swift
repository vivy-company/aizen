//
//  ContentView+Selection.swift
//  aizen
//
//  Created by Codex on 2026-04-03.
//

import CoreData

extension ContentView {
    func decodeSelectedWorktreeByRepository() -> [String: String] {
        WorktreeSelectionPersistence.decodeRepositorySelections(from: selectedWorktreeByRepositoryData)
    }

    func encodeSelectedWorktreeByRepository(_ map: [String: String]) {
        guard let json = WorktreeSelectionPersistence.encodeRepositorySelections(map) else {
            return
        }
        selectedWorktreeByRepositoryData = json
    }

    func getStoredWorktreeId(for repository: Repository) -> UUID? {
        guard let repositoryId = repository.id?.uuidString else { return nil }
        return WorktreeSelectionPersistence.storedWorktreeId(
            for: repositoryId,
            repositorySelectionsJSON: selectedWorktreeByRepositoryData
        )
    }

    func storeWorktreeSelection(_ worktreeId: UUID?, for repository: Repository) {
        guard let repositoryId = repository.id?.uuidString else { return }
        guard let json = WorktreeSelectionPersistence.updatingRepositorySelectionsJSON(
            repositorySelectionsJSON: selectedWorktreeByRepositoryData,
            repositoryId: repositoryId,
            worktreeId: worktreeId
        ) else {
            return
        }
        selectedWorktreeByRepositoryData = json
    }

    func decodeWorktreeMRUOrder() -> [String] {
        WorktreeSelectionPersistence.decodeMRUOrder(from: worktreeMRUOrderData)
    }

    func encodeWorktreeMRUOrder(_ order: [String]) {
        guard let json = WorktreeSelectionPersistence.encodeMRUOrder(order) else {
            return
        }
        worktreeMRUOrderData = json
    }

    func recordWorktreeInMRU(_ worktree: Worktree) {
        guard !worktree.isDeleted, let worktreeId = worktree.id?.uuidString else {
            return
        }

        var order = decodeWorktreeMRUOrder()
        order.removeAll { $0 == worktreeId }
        order.insert(worktreeId, at: 0)

        if order.count > 100 {
            order = Array(order.prefix(100))
        }

        encodeWorktreeMRUOrder(order)
    }

    func quickSwitchToPreviousWorktree() {
        let request: NSFetchRequest<Worktree> = Worktree.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Worktree.lastAccessed, ascending: false)]

        guard let fetchedWorktrees = try? viewContext.fetch(request) else { return }

        guard let target = WorktreeQuickSwitcher.nextTarget(
            from: fetchedWorktrees,
            currentWorktreeId: currentActiveWorktree()?.id?.uuidString,
            mruOrder: decodeWorktreeMRUOrder()
        ) else {
            return
        }

        encodeWorktreeMRUOrder(target.updatedMRUOrder)

        guard let selectedTarget = fetchedWorktrees.first(where: { $0.id == target.worktreeId }) else {
            return
        }

        selectedTarget.lastAccessed = Date()
        try? viewContext.save()
        navigateToWorktree(
            workspaceId: target.workspaceId,
            repoId: target.repositoryId,
            worktreeId: target.worktreeId
        )
    }

    func navigateToWorktree(workspaceId: UUID, repoId: UUID, worktreeId: UUID) {
        guard let workspace = workspaces.first(where: { $0.id == workspaceId }) else {
            return
        }

        selectWorkspace(workspace, preserveSelection: true)

        let allRepositories = (workspace.repositories as? Set<Repository>) ?? []
        let allWorkspaceWorktrees = allRepositories.flatMap { repository -> [Worktree] in
            ((repository.worktrees as? Set<Worktree>) ?? []).filter { !$0.isDeleted }
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
            let worktrees = (crossProjectRepository.worktrees as? Set<Worktree>) ?? []
            if let worktree = worktrees.first(where: { $0.id == worktreeId && !$0.isDeleted }) {
                setCrossProjectSelected(true, preferredWorktree: worktree)
            } else {
                setCrossProjectSelected(true)
            }
            return
        }

        let repositories = visibleRepositories(in: workspace)
        if let repository = repositories.first(where: { $0.id == repoId }) {
            selectRepository(repository)
            let worktrees = (repository.worktrees as? Set<Worktree>) ?? []
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

        let worktrees = (repository.worktrees as? Set<Worktree>) ?? []
        if let restoredWorktreeId = getStoredWorktreeId(for: repository),
           let restoredWorktree = worktrees.first(where: { $0.id == restoredWorktreeId && !$0.isDeleted }) {
            selectWorktree(restoredWorktree)
            return
        }

        if let worktreeId = selectedWorktreeId,
           let uuid = UUID(uuidString: worktreeId),
           let restoredWorktree = worktrees.first(where: { $0.id == uuid && !$0.isDeleted }) {
            selectWorktree(restoredWorktree)
            return
        }

        let candidates = worktrees.filter { !$0.isDeleted }
        selectWorktree(candidates.first(where: { $0.isPrimary }) ?? candidates.first)
    }

    func selectWorktree(_ worktree: Worktree?) {
        if let worktree, worktree.isDeleted {
            selectionStore.selectedWorktree = nil
            selectedWorktreeId = nil
            if let repository = selectionStore.selectedRepository {
                let worktrees = (repository.worktrees as? Set<Worktree>) ?? []
                let fallback = worktrees.first(where: { $0.isPrimary && !$0.isDeleted })
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
