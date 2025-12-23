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
    private let viewContext: NSManagedObjectContext
    private let container: NSPersistentContainer
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen.app", category: "RepositoryManager")

    // Domain services (using libgit2)
    private let statusService = GitStatusService()
    private let branchService = GitBranchService()
    private let worktreeService = GitWorktreeService()
    private let remoteService = GitRemoteService()
    private let fileSystemManager: RepositoryFileSystemManager
    private let postCreateExecutor = PostCreateActionExecutor()

    init(viewContext: NSManagedObjectContext) {
        self.viewContext = viewContext
        self.container = PersistenceController.shared.container
        self.fileSystemManager = RepositoryFileSystemManager()
    }

    // MARK: - Workspace Operations

    func createWorkspace(name: String, colorHex: String? = nil) throws -> Workspace {
        let workspace = Workspace(context: viewContext)
        workspace.id = UUID()
        workspace.name = name
        workspace.colorHex = colorHex

        // Get max order and increment
        let fetchRequest: NSFetchRequest<Workspace> = Workspace.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Workspace.order, ascending: false)]
        fetchRequest.fetchLimit = 1

        if let lastWorkspace = try? viewContext.fetch(fetchRequest).first {
            workspace.order = lastWorkspace.order + 1
        } else {
            workspace.order = 0
        }

        try viewContext.save()
        return workspace
    }

    func deleteWorkspace(_ workspace: Workspace) throws {
        viewContext.delete(workspace)
        try viewContext.save()
    }

    func updateWorkspace(_ workspace: Workspace, name: String? = nil, colorHex: String? = nil) throws {
        if let name = name {
            workspace.name = name
        }
        if let colorHex = colorHex {
            workspace.colorHex = colorHex
        }
        try viewContext.save()
    }

    // MARK: - Repository Operations

    func addExistingRepository(path: String, workspace: Workspace) async throws -> Repository {
        // Validate it's a git repository using libgit2 (async to avoid blocking main thread)
        guard await GitUtils.isGitRepository(at: path) else {
            throw Libgit2Error.notARepository(path)
        }

        // Get main repository path (in case this is a worktree) - async for file I/O
        let mainRepoPath = await GitUtils.getMainRepositoryPath(at: path)

        // Check if repository already exists
        let fetchRequest: NSFetchRequest<Repository> = Repository.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "path == %@", mainRepoPath)

        if let existing = try? viewContext.fetch(fetchRequest).first {
            // Update workspace if different
            existing.workspace = workspace
            try viewContext.save()
            return existing
        }

        // Create new repository
        let repository = Repository(context: viewContext)
        repository.id = UUID()
        repository.path = mainRepoPath
        repository.name = try await remoteService.getRepositoryName(at: mainRepoPath)
        repository.workspace = workspace
        repository.lastUpdated = Date()

        // Scan and add worktrees
        try await scanWorktrees(for: repository)

        try viewContext.save()
        return repository
    }

    func cloneRepository(url: String, destinationPath: String, workspace: Workspace) async throws -> Repository {
        // Extract repo name from URL and append to destination
        let repoName = extractRepoName(from: url)
        let fullPath = (destinationPath as NSString).appendingPathComponent(repoName)

        // Clone the repository
        try await remoteService.clone(url: url, to: fullPath)

        // Add it as an existing repository
        return try await addExistingRepository(path: fullPath, workspace: workspace)
    }

    private func extractRepoName(from url: String) -> String {
        // Handle various URL formats:
        // https://github.com/user/repo.git -> repo
        // git@github.com:user/repo.git -> repo
        // /path/to/repo -> repo
        var name = URL(string: url)?.lastPathComponent ?? url

        // Remove .git suffix if present
        if name.hasSuffix(".git") {
            name = String(name.dropLast(4))
        }

        // If still empty or invalid, use a default
        if name.isEmpty || name == "/" {
            name = "repository"
        }

        return name
    }

    func createNewRepository(path: String, name: String, workspace: Workspace) async throws -> Repository {
        // Construct full path
        let fullPath = (path as NSString).appendingPathComponent(name)

        // Check if directory already exists
        if FileManager.default.fileExists(atPath: fullPath) {
            throw Libgit2Error.unknownError(0, "Directory already exists")
        }

        // Initialize git repository
        try await remoteService.initRepository(at: fullPath)

        // Add as existing repository
        return try await addExistingRepository(path: fullPath, workspace: workspace)
    }

    func deleteRepository(_ repository: Repository) throws {
        let workspace = repository.workspace
        viewContext.delete(repository)
        try viewContext.save()
        // Force refresh the workspace's fault state to trigger UI updates
        workspace?.objectWillChange.send()
    }

    // MARK: - Repository Status and Note Operations

    func updateRepositoryStatus(_ repository: Repository, status: ItemStatus) throws {
        repository.status = status.rawValue
        try viewContext.save()
    }

    func updateRepositoryNote(_ repository: Repository, note: String?) throws {
        repository.note = note
        try viewContext.save()
    }

    // MARK: - Worktree Status and Note Operations

    func updateWorktreeStatus(_ worktree: Worktree, status: ItemStatus) throws {
        worktree.status = status.rawValue
        try viewContext.save()
    }

    func updateWorktreeNote(_ worktree: Worktree, note: String?) throws {
        worktree.note = note
        try viewContext.save()
    }

    func refreshRepository(_ repository: Repository) async throws {
        guard let repositoryPath = repository.path else {
            throw Libgit2Error.invalidPath("Repository path is nil")
        }

        do {
            repository.lastUpdated = Date()
            try await scanWorktrees(for: repository)

            // Save with error handling
            if viewContext.hasChanges {
                try viewContext.save()
            }
        } catch let error as NSError {
            logger.error("Failed to refresh repository \(repositoryPath): \(error.localizedDescription)")

            // Log merge conflict details if present
            if let conflicts = error.userInfo[NSPersistentStoreSaveConflictsErrorKey] as? [NSMergeConflict] {
                for conflict in conflicts {
                    logger.error("Merge conflict: \(conflict.sourceObject.objectID)")
                }
            }

            // Attempt recovery by refreshing the object from persistent store
            viewContext.refresh(repository, mergeChanges: false)
            logger.info("Recovered by refreshing repository from store")

            throw error
        }
    }

    // MARK: - Worktree Operations

    func scanWorktrees(for repository: Repository) async throws {
        guard let repositoryPath = repository.path else {
            throw Libgit2Error.invalidPath("Repository path is nil")
        }

        let worktreeInfos = try await worktreeService.listWorktrees(at: repositoryPath)

        // Build set of valid paths from libgit2
        let validPaths = Set(worktreeInfos.map { $0.path })

        // Get existing worktrees
        let existingWorktrees = (repository.worktrees as? Set<Worktree>) ?? []

        // First pass: delete any worktrees with invalid paths (missing /, duplicates, or not in libgit2 list)
        var seenPaths = Set<String>()
        for wt in existingWorktrees {
            guard var path = wt.path else {
                viewContext.delete(wt)
                continue
            }

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
            if let path = wt.path {
                worktreesByPath[path] = wt
            }
        }

        // Add or update worktrees from libgit2
        for info in worktreeInfos {
            if let existing = worktreesByPath[info.path] {
                // Update existing
                existing.branch = info.branch
                existing.isPrimary = info.isPrimary
            } else {
                // Create new
                let worktree = Worktree(context: viewContext)
                worktree.id = UUID()
                worktree.path = info.path
                worktree.branch = info.branch
                worktree.isPrimary = info.isPrimary
                worktree.repository = repository
            }
        }
    }

    func addWorktree(to repository: Repository, path: String, branch: String, createBranch: Bool, baseBranch: String? = nil) async throws -> Worktree {
        guard let repoPath = repository.path else {
            throw Libgit2Error.invalidPath("Repository path is nil")
        }

        // Ensure ~/aizen/worktrees/{repoName}/ directory exists
        let repoName = URL(fileURLWithPath: repoPath).lastPathComponent
        let worktreesDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("aizen/worktrees")
            .appendingPathComponent(repoName)
        try? FileManager.default.createDirectory(at: worktreesDir, withIntermediateDirectories: true)

        try await worktreeService.addWorktree(at: repoPath, path: path, branch: branch, createBranch: createBranch, baseBranch: baseBranch)

        let worktree = Worktree(context: viewContext)
        worktree.id = UUID()
        worktree.path = path
        worktree.branch = branch
        worktree.isPrimary = false
        worktree.repository = repository
        worktree.lastAccessed = Date()

        try viewContext.save()

        // Execute post-create actions if configured
        await executePostCreateActions(for: repository, newWorktreePath: path)

        return worktree
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
            throw Libgit2Error.worktreeNotFound("Worktree path is nil")
        }
        return try await statusService.hasUnsavedChanges(at: worktreePath)
    }

    func deleteWorktree(_ worktree: Worktree, force: Bool = false) async throws {
        guard let repository = worktree.repository,
              let repoPath = repository.path,
              let worktreePath = worktree.path else {
            throw Libgit2Error.worktreeNotFound("Worktree path is nil")
        }

        try await worktreeService.removeWorktree(at: worktreePath, repoPath: repoPath, force: force)

        viewContext.delete(worktree)
        try viewContext.save()
    }

    func updateWorktreeAccess(_ worktree: Worktree) throws {
        worktree.lastAccessed = Date()
        try viewContext.save()
    }

    // MARK: - Branch Operations

    func getBranches(for repository: Repository) async throws -> [BranchInfo] {
        return try await branchService.listBranches(at: repository.path!, includeRemote: true)
    }

    func getWorktreeStatus(_ worktree: Worktree) async throws -> (branch: String, ahead: Int, behind: Int) {
        guard let path = worktree.path else {
            throw Libgit2Error.worktreeNotFound("Worktree path is nil")
        }

        let branch = try await statusService.getCurrentBranch(at: path)
        let status = try await statusService.getBranchStatus(at: path)

        return (branch, status.ahead, status.behind)
    }

    func mergeFromWorktree(target: Worktree, source: Worktree) async throws -> MergeResult {
        guard let targetPath = target.path else {
            throw Libgit2Error.worktreeNotFound("Target worktree path is nil")
        }

        guard let sourceBranch = source.branch else {
            throw Libgit2Error.worktreeNotFound("Source worktree branch is nil")
        }

        // Validate target worktree has no uncommitted changes
        let hasChanges = try await hasUnsavedChanges(target)
        if hasChanges {
            throw Libgit2Error.uncommittedChanges("Target worktree has uncommitted changes. Please commit or stash them first.")
        }

        // Perform merge
        return try await branchService.mergeBranch(at: targetPath, branch: sourceBranch)
    }

    func switchBranch(_ worktree: Worktree, to branchName: String) async throws {
        guard let path = worktree.path else {
            throw Libgit2Error.worktreeNotFound("Worktree path is nil")
        }

        let originalBranch = worktree.branch
        try await branchService.checkoutBranch(at: path, branch: branchName)

        worktree.branch = branchName
        do {
            try viewContext.save()
        } catch {
            // Rollback on save failure
            worktree.branch = originalBranch
            logger.error("Failed to save branch switch: \(error.localizedDescription)")
            throw error
        }
    }

    func createAndSwitchBranch(_ worktree: Worktree, name: String, from baseBranch: String) async throws {
        guard let path = worktree.path else {
            throw Libgit2Error.worktreeNotFound("Worktree path is nil")
        }

        let originalBranch = worktree.branch
        try await branchService.createBranch(at: path, name: name, from: baseBranch)

        worktree.branch = name
        do {
            try viewContext.save()
        } catch {
            // Rollback on save failure
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
