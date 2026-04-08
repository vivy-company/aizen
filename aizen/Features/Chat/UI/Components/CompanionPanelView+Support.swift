//
//  CompanionPanelView+Support.swift
//  aizen
//

import CoreData
import Foundation

extension CompanionPanelView {
    var panelSubtitle: String {
        switch panel {
        case .terminal:
            return terminalSubtitle
        case .files:
            return worktreePathSubtitle
        case .browser:
            return browserSubtitle
        case .gitDiff:
            return gitDiffSubtitle.isEmpty ? worktreeNameFallback : gitDiffSubtitle
        }
    }

    var terminalSubtitle: String {
        if let session = selectedTerminalSession ?? terminalSessions.last {
            if let title = session.title, !title.isEmpty {
                return title
            }
        }
        return worktreeNameFallback
    }

    var browserSubtitle: String {
        if let session = selectedBrowserSession ?? browserSessions.last {
            if let title = session.title, !title.isEmpty {
                return title
            }
            if let url = session.url, !url.isEmpty {
                return url
            }
        }
        return worktreeNameFallback
    }

    var worktreePathSubtitle: String {
        guard let path = worktree.path, !path.isEmpty else { return "No environment path" }
        return path
    }

    var worktreeNameFallback: String {
        guard let path = worktree.path, !path.isEmpty else { return "Environment" }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    var terminalSessions: [TerminalSession] {
        let sessions = (worktree.terminalSessions as? Set<TerminalSession>) ?? []
        return sessions
            .filter { !$0.isDeleted }
            .sorted { ($0.createdAt ?? Date()) < ($1.createdAt ?? Date()) }
    }

    var selectedTerminalSession: TerminalSession? {
        guard let id = terminalSessionId else { return nil }
        return terminalSessions.first(where: { $0.id == id })
    }

    var browserSessions: [BrowserSession] {
        let sessions = (worktree.browserSessions as? Set<BrowserSession>) ?? []
        return sessions
            .filter { !$0.isDeleted }
            .sorted { ($0.createdAt ?? Date()) < ($1.createdAt ?? Date()) }
    }

    var selectedBrowserSession: BrowserSession? {
        guard let id = browserSessionId else { return nil }
        return browserSessions.first(where: { $0.id == id })
    }
}
