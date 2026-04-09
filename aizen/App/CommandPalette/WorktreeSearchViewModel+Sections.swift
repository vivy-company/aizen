//
//  WorktreeSearchViewModel+Sections.swift
//  aizen
//
//  Created by OpenAI Codex on 03.04.26.
//

import CoreData
import Foundation

@MainActor
extension WorktreeSearchViewModel {
    func buildSections(
        scope: CommandPaletteScope,
        query: String,
        worktrees: [Worktree],
        workspaces: [Workspace],
        currentWorktreeId: String?,
        currentRepositoryId: String?,
        currentWorkspaceId: String?
    ) -> [CommandPaletteSection] {
        switch scope {
        case .all:
            return buildAllSections(
                query: query,
                worktrees: worktrees,
                workspaces: workspaces,
                currentWorktreeId: currentWorktreeId,
                currentRepositoryId: currentRepositoryId,
                currentWorkspaceId: currentWorkspaceId
            )
        case .currentProject:
            return buildCurrentProjectSections(
                query: query,
                worktrees: worktrees,
                currentWorktreeId: currentWorktreeId,
                currentRepositoryId: currentRepositoryId,
                currentWorkspaceId: currentWorkspaceId
            )
        case .workspace:
            return buildWorkspaceSections(
                query: query,
                workspaces: workspaces,
                worktrees: worktrees,
                currentWorktreeId: currentWorktreeId,
                currentRepositoryId: currentRepositoryId,
                currentWorkspaceId: currentWorkspaceId
            )
        case .tabs:
            return buildTabsSections(
                query: query,
                worktrees: worktrees,
                currentWorktreeId: currentWorktreeId,
                currentRepositoryId: currentRepositoryId,
                currentWorkspaceId: currentWorkspaceId,
                includeAllWorktrees: true
            )
        }
    }

    func buildWorktreeItems(
        query: String,
        worktrees: [Worktree],
        currentWorktreeId: String?,
        currentRepositoryId: String?,
        currentWorkspaceId: String?,
        includeCurrentWorktree: Bool
    ) -> [CommandPaletteItem] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowerQuery = trimmedQuery.lowercased()

        let base = worktrees.filter { worktree in
            guard !worktree.isDeleted else { return false }
            guard worktree.repository?.workspace != nil else { return false }
            if !includeCurrentWorktree,
               let currentId = currentWorktreeId,
               let worktreeId = worktree.id?.uuidString,
               currentId == worktreeId {
                return false
            }
            return true
        }

        let ranked = base.compactMap { worktree -> CommandPaletteItem? in
            guard let workspaceId = worktree.repository?.workspace?.id,
                  let repoId = worktree.repository?.id,
                  let worktreeId = worktree.id else {
                return nil
            }

            let workspaceName = worktree.repository?.workspace?.name ?? "Workspace"
            let repoName = worktree.repository?.name ?? "Repository"
            let branchName = worktree.branch ?? "Unknown"
            let subtitle = "\(workspaceName) › \(repoName)"
            let fields = [branchName, repoName, workspaceName, worktree.note ?? ""]

            let queryScore: Double
            if lowerQuery.isEmpty {
                queryScore = 1
            } else {
                queryScore = CommandPaletteScorer.matchScore(query: lowerQuery, fields: fields)
            }
            guard queryScore > 0 else { return nil }

            var score = queryScore
            score += CommandPaletteRecency.boost(for: worktree.lastAccessed)

            if repoId.uuidString == currentRepositoryId {
                score += 120
            }
            if workspaceId.uuidString == currentWorkspaceId {
                score += 40
            }
            if worktree.isPrimary {
                score += 12
            }
            if CommandPaletteWorkspaceSupport.isCrossProjectWorktree(worktree, marker: crossProjectRepositoryMarker) {
                score -= 18
            }

            let isCrossProject = CommandPaletteWorkspaceSupport.isCrossProjectWorktree(worktree, marker: crossProjectRepositoryMarker)
            return CommandPaletteItem(
                id: "worktree-\(worktreeId.uuidString)",
                kind: .worktree,
                title: isCrossProject ? workspaceName : branchName,
                subtitle: isCrossProject ? "All Projects" : subtitle,
                icon: isCrossProject ? "square.stack.3d.up.fill" : (worktree.isPrimary ? "arrow.triangle.branch" : "arrow.triangle.2.circlepath"),
                badgeText: isCrossProject ? "cross-project" : (worktree.isPrimary ? "main" : nil),
                score: score,
                lastAccessed: worktree.lastAccessed,
                workspaceId: workspaceId,
                repoId: repoId,
                worktreeId: worktreeId,
                tabId: nil,
                sessionId: nil
            )
        }

        return ranked.sorted { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            let lhsLast = lhs.lastAccessed ?? .distantPast
            let rhsLast = rhs.lastAccessed ?? .distantPast
            if lhsLast != rhsLast {
                return lhsLast > rhsLast
            }
            return lhs.title.lowercased() < rhs.title.lowercased()
        }
    }

    func buildWorkspaceItems(query: String, workspaces: [Workspace], worktrees: [Worktree]) -> [CommandPaletteItem] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowerQuery = trimmedQuery.lowercased()

        let base = workspaces.filter { $0.id != nil }

        let ranked = base.compactMap { workspace -> CommandPaletteItem? in
            guard let workspaceId = workspace.id else { return nil }
            let workspaceName = workspace.name ?? "Workspace"
            let fallbackWorktree = CommandPaletteWorkspaceSupport.bestWorktree(for: workspace, worktrees: worktrees)

            guard let worktreeId = fallbackWorktree?.id,
                  let repoId = fallbackWorktree?.repository?.id else {
                return nil
            }

            let fields = [workspaceName]
            let queryScore: Double
            if lowerQuery.isEmpty {
                queryScore = 1
            } else {
                queryScore = CommandPaletteScorer.matchScore(query: lowerQuery, fields: fields)
            }
            guard queryScore > 0 else { return nil }

            var score = queryScore
            score += workspaceId.uuidString == currentWorkspaceId ? 120 : 0
            score += CommandPaletteRecency.boost(for: fallbackWorktree?.lastAccessed)

            return CommandPaletteItem(
                id: "workspace-\(workspaceId.uuidString)",
                kind: .workspace,
                title: workspaceName,
                subtitle: "Open most recent environment",
                icon: "folder.badge.gearshape",
                badgeText: nil,
                score: score,
                lastAccessed: fallbackWorktree?.lastAccessed,
                workspaceId: workspaceId,
                repoId: repoId,
                worktreeId: worktreeId,
                tabId: nil,
                sessionId: nil
            )
        }

        return ranked.sorted { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            return lhs.title.lowercased() < rhs.title.lowercased()
        }
    }
}
