//
//  RepositoryManager+Workspace.swift
//  aizen
//
//  Workspace and repository-path management helpers.
//

import CoreData
import Foundation

extension RepositoryManager {
    // MARK: - Workspace Operations

    func createWorkspace(name: String, colorHex: String? = nil) throws -> Workspace {
        let workspace = Workspace(context: viewContext)
        workspace.id = UUID()
        workspace.name = name
        workspace.colorHex = colorHex

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

    // MARK: - Repository Path Validation

    struct MissingRepository: Identifiable {
        let id: UUID
        let repository: Repository
        let lastKnownPath: String
    }

    func validateRepositoryPath(_ repository: Repository) -> Bool {
        guard let path = repository.path else { return false }
        return FileManager.default.fileExists(atPath: path)
    }

    func relocateRepository(_ repository: Repository, to newPath: String) async throws {
        let resolvedPath = normalizedPath(newPath)
        let canonicalPath = GitUtils.isGitRepository(at: resolvedPath)
            ? GitUtils.getMainRepositoryPath(at: resolvedPath)
            : resolvedPath

        repository.path = canonicalPath
        repository.lastUpdated = Date()
        repository.name = URL(fileURLWithPath: canonicalPath).lastPathComponent

        if GitUtils.isGitRepository(at: canonicalPath) {
            try await scanWorktrees(for: repository)
        } else {
            ensurePrimaryEnvironment(for: repository, rootPath: canonicalPath)
        }

        try viewContext.save()
    }
}

extension RepositoryManager {
    func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    func defaultEnvironmentName(for path: String) -> String {
        let name = URL(fileURLWithPath: path).lastPathComponent
        return name.isEmpty ? "Environment" : name
    }

    func ensurePrimaryEnvironment(for repository: Repository, rootPath: String) {
        let environments = (repository.worktrees as? Set<Worktree>) ?? []
        let fallbackName = defaultEnvironmentName(for: rootPath)

        if let primary = environments.first(where: { $0.isPrimary }) {
            primary.path = rootPath
            primary.isPrimary = true
            if primary.branch?.isEmpty ?? true {
                primary.branch = fallbackName
            }
            primary.checkoutTypeValue = WorktreeCheckoutType.primary
            return
        }

        let primary = Worktree(context: viewContext)
        primary.id = UUID()
        primary.path = rootPath
        primary.branch = fallbackName
        primary.isPrimary = true
        primary.checkoutTypeValue = WorktreeCheckoutType.primary
        primary.repository = repository
        primary.lastAccessed = Date()
    }

    func environmentRootDirectory(for repositoryPath: String) -> URL {
        let repoName = URL(fileURLWithPath: repositoryPath).lastPathComponent
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("aizen/worktrees")
            .appendingPathComponent(repoName)
    }
}
