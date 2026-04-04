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

    func buildWorkspaceItems(query: String, workspaces: [Workspace]) -> [CommandPaletteItem] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowerQuery = trimmedQuery.lowercased()

        let base = workspaces.filter { $0.id != nil }

        let ranked = base.compactMap { workspace -> CommandPaletteItem? in
            guard let workspaceId = workspace.id else { return nil }
            let workspaceName = workspace.name ?? "Workspace"
            let fallbackWorktree = CommandPaletteWorkspaceSupport.bestWorktree(for: workspace)

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

    func buildTabAndSessionItems(
        query: String,
        worktrees: [Worktree],
        currentWorktreeId: String?,
        currentRepositoryId: String?,
        currentWorkspaceId: String?,
        includeAllWorktrees: Bool
    ) -> [CommandPaletteItem] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowerQuery = trimmedQuery.lowercased()
        let isEmptyQuery = lowerQuery.isEmpty

        let eligible: [Worktree]
        if includeAllWorktrees {
            eligible = worktrees.filter { !$0.isDeleted && $0.repository?.workspace != nil }
        } else {
            eligible = worktrees.filter { worktree in
                guard !worktree.isDeleted else { return false }
                guard worktree.repository?.workspace != nil else { return false }
                guard let repoId = worktree.repository?.id?.uuidString else { return false }
                return repoId == currentRepositoryId
            }
        }

        guard !eligible.isEmpty else { return [] }

        let currentWorktree = eligible.first(where: { $0.id?.uuidString == currentWorktreeId })
        let prioritized: [Worktree]
        if isEmptyQuery, let currentWorktree {
            prioritized = [currentWorktree]
        } else {
            prioritized = eligible
        }

        let tabDefs = CommandPaletteTabCatalog.visibleDefinitions(using: defaults)
        let includeChatSessions = CommandPaletteTabCatalog.isTabVisible("chat", using: defaults)
        let includeTerminalSessions = CommandPaletteTabCatalog.isTabVisible("terminal", using: defaults)
        let includeBrowserSessions = CommandPaletteTabCatalog.isTabVisible("browser", using: defaults)

        if tabDefs.isEmpty && !includeChatSessions && !includeTerminalSessions && !includeBrowserSessions {
            return []
        }

        var items: [CommandPaletteItem] = []
        items.reserveCapacity(96)

        for worktree in prioritized {
            guard let workspaceId = worktree.repository?.workspace?.id,
                  let repoId = worktree.repository?.id,
                  let worktreeId = worktree.id else {
                continue
            }

            let workspaceName = worktree.repository?.workspace?.name ?? "Workspace"
            let repoName = worktree.repository?.name ?? "Repository"
            let branchName = worktree.branch ?? "Unknown"
            let context = "\(workspaceName) › \(repoName) › \(branchName)"

            for tab in tabDefs {
                let fields = [tab.title, branchName, repoName, workspaceName]
                let queryScore: Double
                if isEmptyQuery {
                    queryScore = worktree.id?.uuidString == currentWorktreeId ? 260 : 0
                } else {
                    queryScore = CommandPaletteScorer.matchScore(query: lowerQuery, fields: fields)
                }
                guard queryScore > 0 else { continue }

                var score = queryScore
                score += CommandPaletteRecency.boost(for: worktree.lastAccessed)
                if repoId.uuidString == currentRepositoryId {
                    score += 44
                }
                if workspaceId.uuidString == currentWorkspaceId {
                    score += 18
                }
                if worktree.id?.uuidString == currentWorktreeId {
                    score += 70
                }

                items.append(
                    CommandPaletteItem(
                        id: "tab-\(worktreeId.uuidString)-\(tab.id)",
                        kind: .tab,
                        title: tab.title,
                        subtitle: context,
                        icon: tab.icon,
                        badgeText: nil,
                        score: score,
                        lastAccessed: worktree.lastAccessed,
                        workspaceId: workspaceId,
                        repoId: repoId,
                        worktreeId: worktreeId,
                        tabId: tab.id,
                        sessionId: nil
                    )
                )
            }

            if includeChatSessions {
                let chatSessions = ((worktree.chatSessions as? Set<ChatSession>) ?? [])
                    .filter { !$0.isDeleted && !$0.archived }
                    .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
                for session in chatSessions {
                    guard let sessionId = session.id else { continue }
                    let title = session.title ?? session.agentName?.capitalized ?? "Chat Session"
                    let fields = [title, branchName, repoName, workspaceName, "chat", session.agentName ?? ""]
                    let queryScore = isEmptyQuery
                        ? (worktree.id?.uuidString == currentWorktreeId ? 220 : 0)
                        : CommandPaletteScorer.matchScore(query: lowerQuery, fields: fields)
                    guard queryScore > 0 else { continue }

                    var score = queryScore
                    score += CommandPaletteRecency.boost(for: worktree.lastAccessed)
                    if worktree.id?.uuidString == currentWorktreeId { score += 58 }

                    items.append(
                        CommandPaletteItem(
                            id: "chat-session-\(sessionId.uuidString)",
                            kind: .chatSession,
                            title: title,
                            subtitle: context,
                            icon: "message",
                            badgeText: nil,
                            score: score,
                            lastAccessed: worktree.lastAccessed,
                            workspaceId: workspaceId,
                            repoId: repoId,
                            worktreeId: worktreeId,
                            tabId: "chat",
                            sessionId: sessionId
                        )
                    )
                }
            }

            if includeTerminalSessions {
                let terminalSessions = ((worktree.terminalSessions as? Set<TerminalSession>) ?? [])
                    .filter { !$0.isDeleted }
                    .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
                for session in terminalSessions {
                    guard let sessionId = session.id else { continue }
                    let title = session.title ?? "Terminal Session"
                    let fields = [title, branchName, repoName, workspaceName, "terminal", "shell"]
                    let queryScore = isEmptyQuery
                        ? (worktree.id?.uuidString == currentWorktreeId ? 200 : 0)
                        : CommandPaletteScorer.matchScore(query: lowerQuery, fields: fields)
                    guard queryScore > 0 else { continue }

                    var score = queryScore
                    score += CommandPaletteRecency.boost(for: worktree.lastAccessed)
                    if worktree.id?.uuidString == currentWorktreeId { score += 48 }

                    items.append(
                        CommandPaletteItem(
                            id: "terminal-session-\(sessionId.uuidString)",
                            kind: .terminalSession,
                            title: title,
                            subtitle: context,
                            icon: "terminal",
                            badgeText: nil,
                            score: score,
                            lastAccessed: worktree.lastAccessed,
                            workspaceId: workspaceId,
                            repoId: repoId,
                            worktreeId: worktreeId,
                            tabId: "terminal",
                            sessionId: sessionId
                        )
                    )
                }
            }

            if includeBrowserSessions {
                let browserSessions = ((worktree.browserSessions as? Set<BrowserSession>) ?? [])
                    .filter { !$0.isDeleted }
                    .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
                for session in browserSessions {
                    guard let sessionId = session.id else { continue }
                    let title = session.title ?? session.url ?? "Browser Session"
                    let fields = [title, branchName, repoName, workspaceName, "browser", session.url ?? ""]
                    let queryScore = isEmptyQuery
                        ? (worktree.id?.uuidString == currentWorktreeId ? 180 : 0)
                        : CommandPaletteScorer.matchScore(query: lowerQuery, fields: fields)
                    guard queryScore > 0 else { continue }

                    var score = queryScore
                    score += CommandPaletteRecency.boost(for: worktree.lastAccessed)
                    if worktree.id?.uuidString == currentWorktreeId { score += 40 }

                    items.append(
                        CommandPaletteItem(
                            id: "browser-session-\(sessionId.uuidString)",
                            kind: .browserSession,
                            title: title,
                            subtitle: context,
                            icon: "globe",
                            badgeText: nil,
                            score: score,
                            lastAccessed: worktree.lastAccessed,
                            workspaceId: workspaceId,
                            repoId: repoId,
                            worktreeId: worktreeId,
                            tabId: "browser",
                            sessionId: sessionId
                        )
                    )
                }
            }
        }

        return items.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            let lhsLast = lhs.lastAccessed ?? .distantPast
            let rhsLast = rhs.lastAccessed ?? .distantPast
            if lhsLast != rhsLast {
                return lhsLast > rhsLast
            }
            return lhs.title.lowercased() < rhs.title.lowercased()
        }
        .prefix(isEmptyQuery ? 40 : 80)
        .map { $0 }
    }
}
