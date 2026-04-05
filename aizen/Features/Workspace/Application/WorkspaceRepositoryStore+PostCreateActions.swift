//
//  WorkspaceRepositoryStore+PostCreateActions.swift
//  aizen
//
//  Post-create action orchestration for new worktrees/environments.
//

import Foundation
import os

extension WorkspaceRepositoryStore {
    func executePostCreateActions(for repository: Repository, newWorktreePath: String) async {
        let actions = repository.postCreateActions
        guard !actions.isEmpty else { return }

        guard let mainWorktreePath = findMainWorktreePath(for: repository) else {
            logger.warning("Could not find main worktree path for post-create actions")
            return
        }

        logger.info("Executing \(actions.filter { $0.enabled }.count) post-create actions")

        let result = await postCreateExecutor.execute(
            actions: actions,
            newWorktreePath: newWorktreePath,
            mainWorktreePath: mainWorktreePath
        )

        if result.success {
            logger.info("Post-create actions completed in \(String(format: "%.2f", result.duration))s")
        } else {
            logger.error("Post-create actions failed: \(result.error ?? "Unknown error")")
        }
    }

    func findMainWorktreePath(for repository: Repository) -> String? {
        if let worktrees = repository.worktrees as? Set<Worktree>,
           let primary = worktrees.first(where: { $0.isPrimary }) {
            return primary.path
        }

        return repository.path
    }
}
