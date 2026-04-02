//
//  WorkspaceRepositoryStore+Branches.swift
//  aizen
//
//  Branch and file-system operations for repositories and worktrees.
//

import CoreData
import Foundation
import os.log

extension WorkspaceRepositoryStore {
    // MARK: - Branch Operations

    func getBranches(for repository: Repository) async throws -> [BranchInfo] {
        guard let path = repository.path else { return [] }
        guard GitUtils.isGitRepository(at: path) else { return [] }
        return try await branchService.listBranches(at: path, includeRemote: true)
    }

    func getWorktreeStatus(_ worktree: Worktree) async throws -> (branch: String, ahead: Int, behind: Int) {
        guard let path = worktree.path else {
            throw Libgit2Error.worktreeNotFound("Environment path is nil")
        }
        guard GitUtils.isGitRepository(at: path) else {
            return (worktree.branch ?? defaultEnvironmentName(for: path), 0, 0)
        }

        let branch = try await statusService.getCurrentBranch(at: path)
        let status = try await statusService.getBranchStatus(at: path)

        return (branch, status.ahead, status.behind)
    }

    func mergeFromWorktree(target: Worktree, source: Worktree) async throws -> MergeResult {
        guard let targetPath = target.path else {
            throw Libgit2Error.worktreeNotFound("Target environment path is nil")
        }
        guard GitUtils.isGitRepository(at: targetPath) else {
            throw Libgit2Error.notARepository(targetPath)
        }

        guard let sourceBranch = source.branch else {
            throw Libgit2Error.worktreeNotFound("Source environment branch is nil")
        }

        let hasChanges = try await hasUnsavedChanges(target)
        if hasChanges {
            throw Libgit2Error.uncommittedChanges(
                "Target environment has uncommitted changes. Please commit or stash them first."
            )
        }

        return try await branchService.mergeBranch(at: targetPath, branch: sourceBranch)
    }

    func switchBranch(_ worktree: Worktree, to branchName: String) async throws {
        guard let path = worktree.path else {
            throw Libgit2Error.worktreeNotFound("Environment path is nil")
        }
        guard GitUtils.isGitRepository(at: path) else {
            throw Libgit2Error.notARepository(path)
        }

        let originalBranch = worktree.branch
        try await branchService.checkoutBranch(at: path, branch: branchName)

        worktree.branch = branchName
        do {
            try viewContext.save()
        } catch {
            worktree.branch = originalBranch
            logger.error("Failed to save branch switch: \(error.localizedDescription)")
            throw error
        }
    }

    func createAndSwitchBranch(_ worktree: Worktree, name: String, from baseBranch: String) async throws {
        guard let path = worktree.path else {
            throw Libgit2Error.worktreeNotFound("Environment path is nil")
        }
        guard GitUtils.isGitRepository(at: path) else {
            throw Libgit2Error.notARepository(path)
        }

        let originalBranch = worktree.branch
        try await branchService.createBranch(at: path, name: name, from: baseBranch)

        worktree.branch = name
        do {
            try viewContext.save()
        } catch {
            worktree.branch = originalBranch
            logger.error("Failed to save branch creation: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - File System Operations

    func openInFinder(_ path: String) {
        fileSystemManager.openInFinder(path)
    }

    func openInTerminal(_ path: String) {
        fileSystemManager.openInTerminal(path)
    }

    func openInEditor(_ path: String) {
        fileSystemManager.openInEditor(path)
    }
}
