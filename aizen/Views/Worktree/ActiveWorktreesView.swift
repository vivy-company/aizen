//
//  ActiveWorktreesView.swift
//  aizen
//
//  Shows active worktrees and allows quick navigation/termination
//

import SwiftUI
import os.log

struct ActiveWorktreesView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Worktree.lastAccessed, ascending: false)],
        animation: .default
    )
    private var worktrees: FetchedResults<Worktree>

    @AppStorage("terminalSessionPersistence") private var sessionPersistence = false

    @State private var showTerminateAllConfirm = false

    private var activeWorktrees: [Worktree] {
        worktrees.filter { worktree in
            guard !worktree.isDeleted else { return false }
            return isActive(worktree)
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            header

            if activeWorktrees.isEmpty {
                emptyState
            } else {
                List(activeWorktrees, id: \.objectID) { worktree in
                    ActiveWorktreeRow(
                        worktree: worktree,
                        chatCount: chatCount(for: worktree),
                        terminalCount: terminalCount(for: worktree),
                        browserCount: browserCount(for: worktree),
                        fileCount: fileCount(for: worktree),
                        onOpen: { navigate(to: worktree) },
                        onTerminate: { terminateSessions(for: worktree) }
                    )
                }
                .listStyle(.inset)
            }
        }
        .padding(16)
        .frame(minWidth: 640, minHeight: 420)
        .alert("Terminate all sessions?", isPresented: $showTerminateAllConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Terminate All", role: .destructive) {
                terminateAll()
            }
        } message: {
            Text("This will close all chat, terminal, browser, and file sessions in active worktrees.")
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Active Worktrees")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Worktrees with open sessions")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Terminate All") {
                showTerminateAllConfirm = true
            }
            .buttonStyle(.borderedProminent)
            .disabled(activeWorktrees.isEmpty)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("No active worktrees")
                .font(.headline)
            Text("Open a chat, terminal, or browser session to see it here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func isActive(_ worktree: Worktree) -> Bool {
        chatCount(for: worktree) > 0 ||
        terminalCount(for: worktree) > 0 ||
        browserCount(for: worktree) > 0 ||
        fileCount(for: worktree) > 0
    }

    private func chatCount(for worktree: Worktree) -> Int {
        let sessions = (worktree.chatSessions as? Set<ChatSession>) ?? []
        return sessions.filter { !$0.isDeleted }.count
    }

    private func terminalCount(for worktree: Worktree) -> Int {
        let sessions = (worktree.terminalSessions as? Set<TerminalSession>) ?? []
        return sessions.filter { !$0.isDeleted }.count
    }

    private func browserCount(for worktree: Worktree) -> Int {
        let sessions = (worktree.browserSessions as? Set<BrowserSession>) ?? []
        return sessions.filter { !$0.isDeleted }.count
    }

    private func fileCount(for worktree: Worktree) -> Int {
        if let session = worktree.fileBrowserSession, !session.isDeleted {
            return 1
        }
        return 0
    }

    private func navigate(to worktree: Worktree) {
        guard let repo = worktree.repository,
              let workspace = repo.workspace,
              let workspaceId = workspace.id,
              let repoId = repo.id,
              let worktreeId = worktree.id else {
            return
        }

        NotificationCenter.default.post(
            name: .navigateToWorktree,
            object: nil,
            userInfo: [
                "workspaceId": workspaceId,
                "repoId": repoId,
                "worktreeId": worktreeId
            ]
        )
    }

    private func terminateAll() {
        for worktree in activeWorktrees {
            terminateSessions(for: worktree)
        }
    }

    private func terminateSessions(for worktree: Worktree) {
        // Chat sessions
        let chats = (worktree.chatSessions as? Set<ChatSession>) ?? []
        for session in chats where !session.isDeleted {
            if let id = session.id {
                ChatSessionManager.shared.removeAgentSession(for: id)
            }
            viewContext.delete(session)
        }

        // Terminal sessions
        let terminals = (worktree.terminalSessions as? Set<TerminalSession>) ?? []
        for session in terminals where !session.isDeleted {
            if let id = session.id {
                TerminalSessionManager.shared.removeAllTerminals(for: id)
            }
            if sessionPersistence, let layoutJSON = session.splitLayout,
               let layout = SplitLayoutHelper.decode(layoutJSON) {
                let paneIds = layout.allPaneIds()
                Task {
                    for paneId in paneIds {
                        await TmuxSessionManager.shared.killSession(paneId: paneId)
                    }
                }
            }
            viewContext.delete(session)
        }

        // Browser sessions
        let browsers = (worktree.browserSessions as? Set<BrowserSession>) ?? []
        for session in browsers where !session.isDeleted {
            viewContext.delete(session)
        }

        // File browser session
        if let session = worktree.fileBrowserSession, !session.isDeleted {
            viewContext.delete(session)
        }

        do {
            try viewContext.save()
        } catch {
            Logger.workspace.error("Failed to terminate sessions: \(error.localizedDescription)")
        }
    }
}

private struct ActiveWorktreeRow: View {
    let worktree: Worktree
    let chatCount: Int
    let terminalCount: Int
    let browserCount: Int
    let fileCount: Int
    let onOpen: () -> Void
    let onTerminate: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(worktreeTitle)
                    .font(.headline)
                Text(worktree.path ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 8) {
                if chatCount > 0 { badge(label: "Chat", count: chatCount) }
                if terminalCount > 0 { badge(label: "Terminal", count: terminalCount) }
                if browserCount > 0 { badge(label: "Browser", count: browserCount) }
                if fileCount > 0 { badge(label: "Files", count: fileCount) }
            }
            Button("Open") {
                onOpen()
            }
            .buttonStyle(.bordered)
            Button("Terminate") {
                onTerminate()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 4)
    }

    private var worktreeTitle: String {
        let repoName = worktree.repository?.name ?? "Worktree"
        if let branch = worktree.branch, !branch.isEmpty {
            return "\(repoName) • \(branch)"
        }
        return repoName
    }

    private func badge(label: String, count: Int) -> some View {
        Text("\(label) \(count)")
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.12))
            .cornerRadius(6)
    }
}
