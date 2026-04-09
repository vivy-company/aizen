//
//  WorktreeSessionSnapshot.swift
//  aizen
//
//  Session summary helpers used by worktree- and repository-level read models.
//

import CoreData
import Foundation

struct WorktreeSessionCounts: Equatable, Sendable {
    let chats: Int
    let terminals: Int
    let browsers: Int
    let files: Int

    static let empty = WorktreeSessionCounts(chats: 0, terminals: 0, browsers: 0, files: 0)

    var activeSurfaceCount: Int {
        chats + terminals + browsers
    }
}

struct WorktreeSessionLists {
    let chatSessions: [ChatSession]
    let terminalSessions: [TerminalSession]
    let browserSessions: [BrowserSession]
}

enum WorktreeSessionSnapshotBuilder {
    static func counts(for worktree: Worktree) -> WorktreeSessionCounts {
        let lists = lists(for: worktree)
        let fileCount = (worktree.fileBrowserSession?.isDeleted == false) ? 1 : 0

        return WorktreeSessionCounts(
            chats: lists.chatSessions.count,
            terminals: lists.terminalSessions.count,
            browsers: lists.browserSessions.count,
            files: fileCount
        )
    }

    static func lists(for worktree: Worktree) -> WorktreeSessionLists {
        WorktreeSessionLists(
            chatSessions: chatSessions(for: worktree),
            terminalSessions: terminalSessions(for: worktree),
            browserSessions: browserSessions(for: worktree)
        )
    }

    static func chatSessions(for worktree: Worktree) -> [ChatSession] {
        let sessions = (worktree.chatSessions as? Set<ChatSession>) ?? []
        return sessions
            .filter { !$0.isDeleted && !$0.archived }
            .sorted {
                let lhsDate = $0.createdAt ?? Date()
                let rhsDate = $1.createdAt ?? Date()
                if lhsDate == rhsDate {
                    return ($0.id?.uuidString ?? "") < ($1.id?.uuidString ?? "")
                }
                return lhsDate < rhsDate
            }
    }

    static func recentChatSessions(for worktree: Worktree, limit: Int? = nil) -> [ChatSession] {
        let sessions = (worktree.chatSessions as? Set<ChatSession>) ?? []
        let recentSessions = sessions
            .filter { session in
                guard !session.isDeleted else { return false }
                guard let messages = session.messages as? Set<ChatMessage> else { return false }
                return messages.contains(where: { $0.role == "user" && !$0.isDeleted })
            }
            .sorted {
                let lhsDate = $0.lastMessageAt ?? $0.createdAt ?? Date.distantPast
                let rhsDate = $1.lastMessageAt ?? $1.createdAt ?? Date.distantPast
                if lhsDate == rhsDate {
                    return ($0.id?.uuidString ?? "") > ($1.id?.uuidString ?? "")
                }
                return lhsDate > rhsDate
            }

        guard let limit else { return recentSessions }
        return Array(recentSessions.prefix(limit))
    }

    static func terminalSessions(for worktree: Worktree) -> [TerminalSession] {
        let sessions = (worktree.terminalSessions as? Set<TerminalSession>) ?? []
        return sessions
            .filter { !$0.isDeleted }
            .sorted { ($0.createdAt ?? Date()) < ($1.createdAt ?? Date()) }
    }

    static func browserSessions(for worktree: Worktree) -> [BrowserSession] {
        let sessions = (worktree.browserSessions as? Set<BrowserSession>) ?? []
        return sessions
            .filter { !$0.isDeleted }
            .sorted { ($0.createdAt ?? Date()) < ($1.createdAt ?? Date()) }
    }
}

enum RepositorySessionSnapshotBuilder {
    static func activeSessionCount(for repository: Repository) -> Int {
        let worktrees = (repository.worktrees as? Set<Worktree>) ?? []
        return worktrees.reduce(0) { total, worktree in
            guard !worktree.isDeleted else { return total }
            return total + WorktreeSessionSnapshotBuilder.counts(for: worktree).activeSurfaceCount
        }
    }
}
