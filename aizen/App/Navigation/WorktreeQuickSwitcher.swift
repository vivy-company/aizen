//
//  WorktreeQuickSwitcher.swift
//  aizen
//
//  Created by Codex on 03.04.26.
//

import CoreData
import Foundation

struct WorktreeQuickSwitchTarget {
    let workspaceId: UUID
    let repositoryId: UUID
    let worktreeId: UUID
    let updatedMRUOrder: [String]
}

enum WorktreeQuickSwitcher {
    static func nextTarget(
        from fetchedWorktrees: [Worktree],
        currentWorktreeId: String?,
        mruOrder: [String]
    ) -> WorktreeQuickSwitchTarget? {
        let available = fetchedWorktrees.filter { worktree in
            guard !worktree.isDeleted else { return false }
            guard worktree.id != nil else { return false }
            guard worktree.repository?.id != nil else { return false }
            guard worktree.repository?.workspace?.id != nil else { return false }
            return true
        }

        let availableById: [String: Worktree] = Dictionary(
            uniqueKeysWithValues: available.compactMap { worktree in
                guard let id = worktree.id?.uuidString else { return nil }
                return (id, worktree)
            }
        )

        var cleanedOrder: [String] = []
        var seen = Set<String>()

        for id in mruOrder where availableById[id] != nil {
            if seen.insert(id).inserted {
                cleanedOrder.append(id)
            }
        }

        if let currentWorktreeId,
           availableById[currentWorktreeId] != nil,
           !cleanedOrder.contains(currentWorktreeId) {
            cleanedOrder.insert(currentWorktreeId, at: 0)
        }

        let targetId: String?
        if let currentWorktreeId,
           cleanedOrder.first == currentWorktreeId {
            targetId = cleanedOrder.dropFirst().first
        } else {
            targetId = cleanedOrder.first(where: { $0 != currentWorktreeId })
        }

        guard let resolvedTargetId = targetId ?? available.first(where: { $0.id?.uuidString != currentWorktreeId })?.id?.uuidString,
              let target = availableById[resolvedTargetId],
              let worktreeId = target.id,
              let repositoryId = target.repository?.id,
              let workspaceId = target.repository?.workspace?.id else {
            return nil
        }

        return WorktreeQuickSwitchTarget(
            workspaceId: workspaceId,
            repositoryId: repositoryId,
            worktreeId: worktreeId,
            updatedMRUOrder: cleanedOrder
        )
    }
}
