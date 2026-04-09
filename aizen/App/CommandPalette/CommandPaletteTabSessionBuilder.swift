//
//  CommandPaletteTabSessionBuilder.swift
//  aizen
//
//  Created by OpenAI Codex on 05.04.26.
//

import CoreData
import Foundation

@MainActor
extension WorktreeSearchViewModel {
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

        let tabDefinitions = CommandPaletteTabCatalog.visibleDefinitions(using: defaults)
        let includeChatSessions = CommandPaletteTabCatalog.isTabVisible("chat", using: defaults)
        let includeTerminalSessions = CommandPaletteTabCatalog.isTabVisible("terminal", using: defaults)
        let includeBrowserSessions = CommandPaletteTabCatalog.isTabVisible("browser", using: defaults)

        if tabDefinitions.isEmpty && !includeChatSessions && !includeTerminalSessions && !includeBrowserSessions {
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

            for tab in tabDefinitions {
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
                let chatSessions = Array(WorktreeSessionSnapshotBuilder.chatSessions(for: worktree).reversed())
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
                let terminalSessions = Array(WorktreeSessionSnapshotBuilder.terminalSessions(for: worktree).reversed())
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
                let browserSessions = Array(WorktreeSessionSnapshotBuilder.browserSessions(for: worktree).reversed())
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
