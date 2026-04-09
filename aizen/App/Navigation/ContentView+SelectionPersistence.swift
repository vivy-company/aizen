//
//  ContentView+SelectionPersistence.swift
//  aizen
//
//  Created by Codex on 2026-04-09.
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
        let fetchedWorktrees = workspaceGraphQueryController.worktrees

        guard let target = WorktreeQuickSwitcher.nextTarget(
            from: fetchedWorktrees,
            currentWorktreeId: currentActiveWorktree()?.id?.uuidString,
            mruOrder: decodeWorktreeMRUOrder()
        ) else {
            return
        }

        encodeWorktreeMRUOrder(target.updatedMRUOrder)

        guard let selectedTarget = workspaceGraphQueryController.worktree(id: target.worktreeId) else {
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
}
