//
//  RepositoryManager+Repositories.swift
//  aizen
//
//  Repository CRUD, refresh, and metadata operations.
//

import Combine
import CoreData
import Foundation
import os.log

extension RepositoryManager {
    // MARK: - Repository Operations

    func addExistingRepository(path: String, workspace: Workspace) async throws -> Repository {
        let resolvedPath = normalizedPath(path)
        let isGitRepository = GitUtils.isGitRepository(at: resolvedPath)
        let mainRepoPath = isGitRepository ? GitUtils.getMainRepositoryPath(at: resolvedPath) : resolvedPath

        let fetchRequest: NSFetchRequest<Repository> = Repository.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "path == %@", mainRepoPath)

        if let existing = try? viewContext.fetch(fetchRequest).first {
            existing.workspace = workspace
            existing.lastUpdated = Date()

            if isGitRepository {
                try await scanWorktrees(for: existing)
            } else {
                ensurePrimaryEnvironment(for: existing, rootPath: mainRepoPath)
            }

            try viewContext.save()
            return existing
        }

        let repository = Repository(context: viewContext)
        repository.id = UUID()
        repository.path = mainRepoPath
        if isGitRepository {
            repository.name = (try? await remoteService.getRepositoryName(at: mainRepoPath))
                ?? defaultEnvironmentName(for: mainRepoPath)
        } else {
            repository.name = defaultEnvironmentName(for: mainRepoPath)
        }
        repository.workspace = workspace
        repository.lastUpdated = Date()

        if isGitRepository {
            try await scanWorktrees(for: repository)
        } else {
            ensurePrimaryEnvironment(for: repository, rootPath: mainRepoPath)
        }

        try viewContext.save()
        return repository
    }

    func cloneRepository(url: String, destinationPath: String, workspace: Workspace) async throws -> Repository {
        let repoName = extractRepoName(from: url)
        let fullPath = (destinationPath as NSString).appendingPathComponent(repoName)

        try await remoteService.clone(url: url, to: fullPath)
        return try await addExistingRepository(path: fullPath, workspace: workspace)
    }

    func listSubmodules(for repository: Repository) async -> [GitSubmoduleInfo] {
        guard let path = repository.path else { return [] }
        guard GitUtils.isGitRepository(at: path) else { return [] }

        do {
            return try await submoduleService.listSubmodules(at: path)
        } catch {
            logger.error("Failed to detect submodules: \(error.localizedDescription)")
            return []
        }
    }

    func createNewRepository(path: String, name: String, workspace: Workspace) async throws -> Repository {
        let fullPath = (path as NSString).appendingPathComponent(name)

        if FileManager.default.fileExists(atPath: fullPath) {
            throw Libgit2Error.unknownError(0, "Directory already exists")
        }

        try await remoteService.initRepository(at: fullPath)
        return try await addExistingRepository(path: fullPath, workspace: workspace)
    }

    func deleteRepository(_ repository: Repository) throws {
        let workspace = repository.workspace
        viewContext.delete(repository)
        try viewContext.save()
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
            throw Libgit2Error.invalidPath("Project path is nil")
        }

        guard FileManager.default.fileExists(atPath: repositoryPath) else {
            throw Libgit2Error.repositoryPathMissing(repositoryPath)
        }

        do {
            repository.lastUpdated = Date()
            if GitUtils.isGitRepository(at: repositoryPath) {
                try await scanWorktrees(for: repository)
            } else {
                ensurePrimaryEnvironment(for: repository, rootPath: repositoryPath)
            }

            if viewContext.hasChanges {
                try viewContext.save()
            }
        } catch let error as NSError {
            logger.error("Failed to refresh repository \(repositoryPath): \(error.localizedDescription)")

            if let conflicts = error.userInfo[NSPersistentStoreSaveConflictsErrorKey] as? [NSMergeConflict] {
                for conflict in conflicts {
                    logger.error("Merge conflict: \(conflict.sourceObject.objectID)")
                }
            }

            viewContext.refresh(repository, mergeChanges: false)
            logger.info("Recovered by refreshing repository from store")

            throw error
        }
    }
}

extension RepositoryManager {
    func extractRepoName(from url: String) -> String {
        var name = URL(string: url)?.lastPathComponent ?? url

        if name.hasSuffix(".git") {
            name = String(name.dropLast(4))
        }

        if name.isEmpty || name == "/" {
            name = "repository"
        }

        return name
    }
}
