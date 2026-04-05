//
//  WorkspaceRepositoryStore+Worktrees.swift
//  aizen
//
//  Worktree lifecycle and post-create orchestration.
//

import CoreData
import Foundation
import os.log

extension WorkspaceRepositoryStore {
    // MARK: - Worktree Operations

    func initializeGit(at path: String) async throws {
        let normalized = normalizedPath(path)
        guard FileManager.default.fileExists(atPath: normalized) else {
            throw Libgit2Error.invalidPath("Path does not exist: \(normalized)")
        }

        if GitUtils.isGitRepository(at: normalized) {
            return
        }

        try await remoteService.initRepository(at: normalized)
    }

    func hasUnsavedChanges(_ worktree: Worktree) async throws -> Bool {
        guard let worktreePath = worktree.path else {
            throw Libgit2Error.worktreeNotFound("Environment path is nil")
        }
        guard GitUtils.isGitRepository(at: worktreePath) else {
            return false
        }
        return try await statusService.hasUnsavedChanges(at: worktreePath)
    }

    func deleteWorktree(_ worktree: Worktree, force: Bool = false) async throws {
        if worktree.checkoutTypeValue == .independent {
            viewContext.delete(worktree)
            try viewContext.save()
            return
        }

        guard let repository = worktree.repository,
              let repoPath = repository.path,
              let worktreePath = worktree.path else {
            throw Libgit2Error.worktreeNotFound("Environment path is nil")
        }

        if GitUtils.isGitRepository(at: repoPath) {
            try await worktreeService.removeWorktree(at: worktreePath, repoPath: repoPath, force: force)
        }

        viewContext.delete(worktree)
        try viewContext.save()
    }

    func updateWorktreeAccess(_ worktree: Worktree) throws {
        worktree.lastAccessed = Date()
        try viewContext.save()
    }
}

extension WorkspaceRepositoryStore {
}
