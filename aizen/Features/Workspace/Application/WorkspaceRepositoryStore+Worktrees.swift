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

    func scanWorktrees(for repository: Repository) async throws {
        guard let repositoryPath = repository.path else {
            throw Libgit2Error.invalidPath("Project path is nil")
        }

        let canonicalPath = normalizedPath(repositoryPath)
        repository.path = canonicalPath

        guard GitUtils.isGitRepository(at: canonicalPath) else {
            ensurePrimaryEnvironment(for: repository, rootPath: canonicalPath)
            return
        }

        let worktreeInfos = try await worktreeService.listWorktrees(at: canonicalPath)
        let validPaths = Set(worktreeInfos.map { normalizedPath($0.path) })
        let existingWorktrees = (repository.worktrees as? Set<Worktree>) ?? []

        var seenPaths = Set<String>()
        for worktree in existingWorktrees {
            if worktree.checkoutTypeValue == .independent {
                continue
            }

            guard var path = worktree.path else {
                viewContext.delete(worktree)
                continue
            }

            path = normalizedPath(path)
            worktree.path = path

            if !path.hasPrefix("/") {
                path = "/" + path
                worktree.path = path
            }

            if !validPaths.contains(path) || seenPaths.contains(path) {
                viewContext.delete(worktree)
            } else {
                seenPaths.insert(path)
            }
        }

        let remainingWorktrees = (repository.worktrees as? Set<Worktree>) ?? []
        var worktreesByPath: [String: Worktree] = [:]
        for worktree in remainingWorktrees where worktree.checkoutTypeValue != .independent {
            if let path = worktree.path {
                worktreesByPath[path] = worktree
            }
        }

        for info in worktreeInfos {
            let normalizedInfoPath = normalizedPath(info.path)
            if let existing = worktreesByPath[normalizedInfoPath] {
                existing.branch = info.branch
                existing.isPrimary = info.isPrimary
                existing.checkoutTypeValue = info.isPrimary ? .primary : .linked
            } else {
                let worktree = Worktree(context: viewContext)
                worktree.id = UUID()
                worktree.path = normalizedInfoPath
                worktree.branch = info.branch
                worktree.isPrimary = info.isPrimary
                worktree.checkoutTypeValue = info.isPrimary ? .primary : .linked
                worktree.repository = repository
            }
        }
    }

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
