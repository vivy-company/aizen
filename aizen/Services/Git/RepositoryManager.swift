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

    // Domain services
    private let executor: GitCommandExecutor
    private let statusService: GitStatusService
    private let branchService: GitBranchService
    private let worktreeService: GitWorktreeService
    private let remoteService: GitRemoteService
    private let fileSystemManager: RepositoryFileSystemManager

    init(viewContext: NSManagedObjectContext) {
        self.viewContext = viewContext
        self.container = PersistenceController.shared.container

        // Initialize domain services
        self.executor = GitCommandExecutor()
        self.statusService = GitStatusService(executor: executor)
        self.branchService = GitBranchService(executor: executor)
        self.worktreeService = GitWorktreeService(executor: executor)
        self.remoteService = GitRemoteService(executor: executor)
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
        // Validate it's a git repository
        guard await executor.isGitRepository(at: path) else {
            throw GitError.notAGitRepository
        }

        // Get main repository path (in case this is a worktree)
        let mainRepoPath = await executor.getMainRepositoryPath(at: path)

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
        // Clone the repository
        try await remoteService.clone(url: url, to: destinationPath)

        // Add it as an existing repository
        return try await addExistingRepository(path: destinationPath, workspace: workspace)
    }

    func createNewRepository(path: String, name: String, workspace: Workspace) async throws -> Repository {
        // Construct full path
        let fullPath = (path as NSString).appendingPathComponent(name)

        // Check if directory already exists
        if FileManager.default.fileExists(atPath: fullPath) {
            throw GitError.commandFailed(message: "Directory already exists")
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

    func refreshRepository(_ repository: Repository) async throws {
        guard let repositoryPath = repository.path else {
            throw GitError.invalidPath
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
            throw GitError.invalidPath
        }

        let worktreeInfos = try await worktreeService.listWorktrees(at: repositoryPath)

        // Get existing worktrees
        let existingWorktrees = (repository.worktrees as? Set<Worktree>) ?? []
        var existingPaths = Set(existingWorktrees.map { $0.path! })

        // Add or update worktrees
        for info in worktreeInfos {
            if let existing = existingWorktrees.first(where: { $0.path == info.path }) {
                // Update existing
                existing.branch = info.branch
                existing.isPrimary = info.isPrimary
                existingPaths.remove(info.path)
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

        // Remove worktrees that no longer exist
        for path in existingPaths {
            if let worktree = existingWorktrees.first(where: { $0.path == path }) {
                // Verify the directory doesn't exist before deleting
                if !FileManager.default.fileExists(atPath: path) {
                    viewContext.delete(worktree)
                }
            }
        }
    }

    func addWorktree(to repository: Repository, path: String, branch: String, createBranch: Bool, baseBranch: String? = nil) async throws -> Worktree {
        guard let repoPath = repository.path else {
            throw GitError.invalidPath
        }

        // Ensure .aizen directory exists and is ignored
        let aizenDir = URL(fileURLWithPath: repoPath).appendingPathComponent(".aizen")
        try? FileManager.default.createDirectory(at: aizenDir, withIntermediateDirectories: true)

        // Add .aizen to .gitignore if not already there
        let gitignorePath = URL(fileURLWithPath: repoPath).appendingPathComponent(".gitignore")
        if FileManager.default.fileExists(atPath: gitignorePath.path) {
            if let gitignoreContent = try? String(contentsOf: gitignorePath, encoding: .utf8) {
                if !gitignoreContent.contains(".aizen") {
                    let newContent = gitignoreContent + "\n.aizen/\n"
                    try? newContent.write(to: gitignorePath, atomically: true, encoding: .utf8)
                }
            }
        } else {
            try? ".aizen/\n".write(to: gitignorePath, atomically: true, encoding: .utf8)
        }

        try await worktreeService.addWorktree(at: repoPath, path: path, branch: branch, createBranch: createBranch, baseBranch: baseBranch)

        let worktree = Worktree(context: viewContext)
        worktree.id = UUID()
        worktree.path = path
        worktree.branch = branch
        worktree.isPrimary = false
        worktree.repository = repository
        worktree.lastAccessed = Date()

        try viewContext.save()
        return worktree
    }

    func hasUnsavedChanges(_ worktree: Worktree) async throws -> Bool {
        guard let worktreePath = worktree.path else {
            throw GitError.worktreeNotFound
        }
        return try await statusService.hasUnsavedChanges(at: worktreePath)
    }

    func deleteWorktree(_ worktree: Worktree, force: Bool = false) async throws {
        guard let repository = worktree.repository,
              let repoPath = repository.path,
              let worktreePath = worktree.path else {
            throw GitError.worktreeNotFound
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
            throw GitError.worktreeNotFound
        }

        let branch = try await statusService.getCurrentBranch(at: path)
        let status = try await statusService.getBranchStatus(at: path)

        return (branch, status.ahead, status.behind)
    }

    func mergeFromWorktree(target: Worktree, source: Worktree) async throws -> MergeResult {
        guard let targetPath = target.path else {
            throw GitError.worktreeNotFound
        }

        guard let sourceBranch = source.branch else {
            throw GitError.worktreeNotFound
        }

        // Validate target worktree has no uncommitted changes
        let hasChanges = try await hasUnsavedChanges(target)
        if hasChanges {
            throw GitError.commandFailed(message: "Target worktree has uncommitted changes. Please commit or stash them first.")
        }

        // Perform merge
        return try await branchService.mergeBranch(at: targetPath, branch: sourceBranch)
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
