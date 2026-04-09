//
//  CrossProjectWorkspaceCoordinator.swift
//  aizen
//
//  Created by Codex on 03.04.26.
//

import CoreData
import Foundation

struct CrossProjectWorkspaceCoordinator {
    let viewContext: NSManagedObjectContext
    let repositoryMarker: String
    let workspaceGraphQueryController: WorkspaceGraphQueryController

    func ensureWorktree(for workspace: Workspace, visibleRepositories: [Repository]) throws -> Worktree {
        let rootURL = try prepareCrossProjectDirectory(for: workspace, visibleRepositories: visibleRepositories)

        let repository = workspaceGraphQueryController
            .repositories(in: workspace)
            .first { $0.isCrossProject || $0.note == repositoryMarker }
            ?? Repository(context: viewContext)
        if repository.id == nil {
            repository.id = UUID()
        }
        repository.name = "Cross-Project"
        repository.path = rootURL.path
        repository.note = repositoryMarker
        repository.isCrossProject = true
        repository.status = "active"
        repository.workspace = workspace
        repository.lastUpdated = Date()

        let existingWorktrees = workspaceGraphQueryController.worktrees(in: repository)
        let worktree = existingWorktrees.first(where: { $0.isPrimary }) ?? existingWorktrees.first ?? Worktree(context: viewContext)
        if worktree.id == nil {
            worktree.id = UUID()
        }
        worktree.path = rootURL.path
        worktree.branch = "workspace"
        worktree.isPrimary = true
        worktree.checkoutTypeValue = .primary
        worktree.repository = repository
        worktree.lastAccessed = Date()

        try viewContext.save()
        return worktree
    }

    private func crossProjectRootURL(for workspace: Workspace) throws -> URL {
        guard let workspaceId = workspace.id else {
            throw NSError(domain: "AizenCrossProject", code: 1, userInfo: [NSLocalizedDescriptionKey: "Workspace identifier is missing"])
        }

        let candidates = workspaceGraphQueryController.workspaces.compactMap { candidate -> WorkspacePathCandidate? in
            guard let candidateID = candidate.id else {
                return nil
            }
            return WorkspacePathCandidate(id: candidateID, name: candidate.name)
        }

        return CrossProjectWorkspacePath.rootURL(
            for: workspaceId,
            workspaceName: workspace.name,
            allWorkspaces: candidates
        )
    }

    private func prepareCrossProjectDirectory(for workspace: Workspace, visibleRepositories: [Repository]) throws -> URL {
        let fileManager = FileManager.default
        let rootURL = try crossProjectRootURL(for: workspace)

        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let existingItems = try fileManager.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil)
        for itemURL in existingItems {
            try? fileManager.removeItem(at: itemURL)
        }

        var usedNames = Set<String>()
        for repository in visibleRepositories {
            guard let sourcePath = repository.path, fileManager.fileExists(atPath: sourcePath) else {
                continue
            }

            let fallbackName = URL(fileURLWithPath: sourcePath).lastPathComponent
            let rawName = (repository.name?.isEmpty == false ? repository.name! : fallbackName)
            let sanitizedName = rawName
                .replacingOccurrences(of: "/", with: "-")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let baseName = sanitizedName.isEmpty ? "project" : sanitizedName

            var linkName = baseName
            var suffix = 2
            while usedNames.contains(linkName) {
                linkName = "\(baseName)-\(suffix)"
                suffix += 1
            }
            usedNames.insert(linkName)

            let linkPath = rootURL.appendingPathComponent(linkName).path
            if fileManager.fileExists(atPath: linkPath) {
                try? fileManager.removeItem(atPath: linkPath)
            }

            try fileManager.createSymbolicLink(atPath: linkPath, withDestinationPath: sourcePath)
        }

        return rootURL
    }
}
