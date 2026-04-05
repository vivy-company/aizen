//
//  WorkspaceRepositoryStore+LinkedEnvironment.swift
//  aizen
//
//  Linked worktree/environment creation flow.
//

import CoreData
import Foundation
import os

extension WorkspaceRepositoryStore {
    func addLinkedEnvironment(
        to repository: Repository,
        path: String,
        branch: String,
        createBranch: Bool,
        baseBranch: String? = nil,
        submoduleOptions: LinkedEnvironmentSubmoduleOptions = .disabled,
        runPostCreateActions: Bool = true
    ) async throws -> Worktree {
        guard let repoPath = repository.path else {
            throw Libgit2Error.invalidPath("Project path is nil")
        }
        guard GitUtils.isGitRepository(at: repoPath) else {
            throw Libgit2Error.notARepository(repoPath)
        }

        let worktreesDir = environmentRootDirectory(for: repoPath)
        try? FileManager.default.createDirectory(at: worktreesDir, withIntermediateDirectories: true)

        let normalizedEnvironmentPath = normalizedPath(path)
        try await worktreeService.addWorktree(
            at: repoPath,
            path: normalizedEnvironmentPath,
            branch: branch,
            createBranch: createBranch,
            baseBranch: baseBranch
        )

        if submoduleOptions.initialize {
            do {
                try await submoduleService.initializeSubmodules(
                    at: normalizedEnvironmentPath,
                    recursive: submoduleOptions.recursive,
                    paths: submoduleOptions.paths
                )
                if submoduleOptions.matchBranchToEnvironment {
                    try await submoduleService.checkoutMatchingBranch(
                        at: normalizedEnvironmentPath,
                        branchName: branch,
                        paths: submoduleOptions.paths
                    )
                }
            } catch {
                logger.error("Submodule initialization failed: \(error.localizedDescription)")
                try? await worktreeService.removeWorktree(
                    at: normalizedEnvironmentPath,
                    repoPath: repoPath,
                    force: true
                )
                throw error
            }
        }

        let worktree = Worktree(context: viewContext)
        worktree.id = UUID()
        worktree.path = normalizedEnvironmentPath
        worktree.branch = branch
        worktree.isPrimary = false
        worktree.checkoutTypeValue = .linked
        worktree.repository = repository
        worktree.lastAccessed = Date()

        try viewContext.save()

        if runPostCreateActions {
            await executePostCreateActions(for: repository, newWorktreePath: normalizedEnvironmentPath)
        }

        return worktree
    }

    func addWorktree(
        to repository: Repository,
        path: String,
        branch: String,
        createBranch: Bool,
        baseBranch: String? = nil,
        runPostCreateActions: Bool = true
    ) async throws -> Worktree {
        try await addLinkedEnvironment(
            to: repository,
            path: path,
            branch: branch,
            createBranch: createBranch,
            baseBranch: baseBranch,
            runPostCreateActions: runPostCreateActions
        )
    }
}
