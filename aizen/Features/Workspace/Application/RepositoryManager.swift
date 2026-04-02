//
//  RepositoryManager.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import Foundation
import CoreData
import AppKit
import Combine
import os.log

@MainActor
class RepositoryManager: ObservableObject {
    enum IndependentEnvironmentMethod: String, CaseIterable {
        case clone
        case copy
    }

    struct LinkedEnvironmentSubmoduleOptions: Sendable {
        let initialize: Bool
        let recursive: Bool
        let paths: [String]
        let matchBranchToEnvironment: Bool

        nonisolated static let disabled = LinkedEnvironmentSubmoduleOptions(
            initialize: false,
            recursive: true,
            paths: [],
            matchBranchToEnvironment: false
        )
    }

    let viewContext: NSManagedObjectContext
    let container: NSPersistentContainer
    let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen.app", category: "RepositoryManager")

    // Domain services (using libgit2)
    let statusService = GitStatusService()
    let branchService = GitBranchService()
    let worktreeService = GitWorktreeService()
    let remoteService = GitRemoteService()
    let submoduleService = GitSubmoduleService()
    let fileSystemManager: RepositoryFileSystemManager
    let postCreateExecutor = PostCreateActionExecutor()

    init(viewContext: NSManagedObjectContext) {
        self.viewContext = viewContext
        self.container = PersistenceController.shared.container
        self.fileSystemManager = RepositoryFileSystemManager()
    }

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

        // Build set of valid paths from libgit2
        let validPaths = Set(worktreeInfos.map { normalizedPath($0.path) })

        // Get existing worktrees
        let existingWorktrees = (repository.worktrees as? Set<Worktree>) ?? []

        // First pass: delete invalid linked/primary worktrees, keep independent environments untouched.
        var seenPaths = Set<String>()
        for wt in existingWorktrees {
            if wt.checkoutTypeValue == .independent {
                continue
            }

            guard var path = wt.path else {
                viewContext.delete(wt)
                continue
            }

            path = normalizedPath(path)
            wt.path = path

            // Fix path if missing leading /
            if !path.hasPrefix("/") {
                path = "/" + path
                wt.path = path
            }

            // Delete if not in valid paths from libgit2 or if duplicate
            if !validPaths.contains(path) || seenPaths.contains(path) {
                viewContext.delete(wt)
            } else {
                seenPaths.insert(path)
            }
        }

        // Build map of remaining worktrees by path
        let remainingWorktrees = (repository.worktrees as? Set<Worktree>) ?? []
        var worktreesByPath: [String: Worktree] = [:]
        for wt in remainingWorktrees {
            if wt.checkoutTypeValue == .independent {
                continue
            }
            if let path = wt.path {
                worktreesByPath[path] = wt
            }
        }

        // Add or update worktrees from libgit2
        for info in worktreeInfos {
            let normalizedInfoPath = normalizedPath(info.path)
            if let existing = worktreesByPath[normalizedInfoPath] {
                // Update existing
                existing.branch = info.branch
                existing.isPrimary = info.isPrimary
                existing.checkoutTypeValue = info.isPrimary ? .primary : .linked
            } else {
                // Create new
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

        // Ensure ~/aizen/worktrees/{repoName}/ directory exists
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
                // Roll back partially-created linked environment to avoid leaving broken state.
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

    func addIndependentEnvironment(
        to repository: Repository,
        path: String,
        sourcePath: String,
        method: IndependentEnvironmentMethod,
        runPostCreateActions: Bool = true
    ) async throws -> Worktree {
        let source = normalizedPath(sourcePath)
        let destination = normalizedPath(path)

        guard FileManager.default.fileExists(atPath: source) else {
            throw Libgit2Error.invalidPath("Source path not found: \(source)")
        }
        guard !FileManager.default.fileExists(atPath: destination) else {
            throw Libgit2Error.unknownError(0, "Directory already exists")
        }

        let destinationParent = URL(fileURLWithPath: destination).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: destinationParent, withIntermediateDirectories: true)

        switch method {
        case .clone:
            guard GitUtils.isGitRepository(at: source) else {
                throw Libgit2Error.notARepository(source)
            }
            let result = try await ProcessExecutor.shared.executeWithOutput(
                executable: "/usr/bin/git",
                arguments: ["clone", "--local", source, destination],
                environment: ShellEnvironment.loadUserShellEnvironment()
            )
            guard result.succeeded else {
                let message = result.stderr.isEmpty ? result.stdout : result.stderr
                throw Libgit2Error.unknownError(result.exitCode, message)
            }
        case .copy:
            try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)
            let result = try await ProcessExecutor.shared.executeWithOutput(
                executable: "/usr/bin/rsync",
                arguments: ["-a", "--exclude", ".git", "\(source)/", "\(destination)/"]
            )
            guard result.succeeded else {
                let message = result.stderr.isEmpty ? result.stdout : result.stderr
                throw Libgit2Error.unknownError(result.exitCode, message)
            }
        }

        let environmentName = defaultEnvironmentName(for: destination)
        let branchName: String
        if GitUtils.isGitRepository(at: destination) {
            branchName = (try? await statusService.getCurrentBranch(at: destination)) ?? environmentName
        } else {
            branchName = environmentName
        }

        let environment = Worktree(context: viewContext)
        environment.id = UUID()
        environment.path = destination
        environment.branch = branchName
        environment.isPrimary = false
        environment.checkoutTypeValue = .independent
        environment.repository = repository
        environment.lastAccessed = Date()

        try viewContext.save()
        if runPostCreateActions {
            await executePostCreateActions(for: repository, newWorktreePath: destination)
        }
        return environment
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

    /// Execute post-create actions for a repository
    private func executePostCreateActions(for repository: Repository, newWorktreePath: String) async {
        let actions = repository.postCreateActions
        guard !actions.isEmpty else { return }

        // Find main worktree path
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

    /// Find the main (primary) worktree path for a repository
    private func findMainWorktreePath(for repository: Repository) -> String? {
        // First try to find a worktree marked as primary
        if let worktrees = repository.worktrees as? Set<Worktree>,
           let primary = worktrees.first(where: { $0.isPrimary }) {
            return primary.path
        }

        // Otherwise use the repository path itself (it's the main worktree)
        return repository.path
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
