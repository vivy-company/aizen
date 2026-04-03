import CoreData
import Foundation

extension ActiveWorktreesView {
    func buildSeed(for worktree: Worktree) -> ActiveWorktreesMonitorRowSeed {
        let counts = sessionCounts(for: worktree)
        let runtime = terminalRuntime(for: worktree)
        let repository = worktree.repository?.name ?? "Environment"
        let branch = worktree.branch?.isEmpty == false ? worktree.branch! : "detached"

        return ActiveWorktreesMonitorRowSeed(
            id: worktree.objectID.uriRepresentation().absoluteString,
            worktree: worktree,
            processName: "\(repository) • \(branch)",
            workspaceName: worktree.repository?.workspace?.name ?? "Other",
            path: worktree.path ?? "",
            counts: counts,
            runtime: runtime,
            lastAccessed: worktree.lastAccessed ?? .distantPast
        )
    }

    func activityScore(for seed: ActiveWorktreesMonitorRowSeed) -> Double {
        let minutesSinceAccess = max(0, Date().timeIntervalSince(seed.lastAccessed) / 60)
        let recency = max(0.25, min(1.0, 1.15 - (minutesSinceAccess / 240.0)))

        let sessionWeight =
            (Double(seed.counts.chats) * 0.8) +
            (Double(seed.counts.terminals) * 2.0) +
            (Double(seed.counts.browsers) * 1.4) +
            (Double(seed.counts.files) * 0.4)

        let runtimeWeight =
            (Double(seed.runtime.livePanes) * 0.8) +
            (Double(seed.runtime.runningPanes) * 1.8)

        return max(0.2, (sessionWeight + runtimeWeight + 0.4) * recency)
    }

    func worktreeSort(lhs: Worktree, rhs: Worktree) -> Bool {
        let lhsDate = lhs.lastAccessed ?? .distantPast
        let rhsDate = rhs.lastAccessed ?? .distantPast
        if lhsDate != rhsDate { return lhsDate > rhsDate }
        return (lhs.path ?? "").localizedCaseInsensitiveCompare(rhs.path ?? "") == .orderedAscending
    }

    func isActive(_ worktree: Worktree) -> Bool {
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

    private func sessionCounts(for worktree: Worktree) -> ActiveWorktreesSessionCounts {
        ActiveWorktreesSessionCounts(
            chats: chatCount(for: worktree),
            terminals: terminalCount(for: worktree),
            browsers: browserCount(for: worktree),
            files: fileCount(for: worktree)
        )
    }

    private func terminalRuntime(for worktree: Worktree) -> ActiveWorktreesTerminalRuntimeSnapshot {
        let terminalSessions = ((worktree.terminalSessions as? Set<TerminalSession>) ?? [])
            .filter { !$0.isDeleted }

        var expectedPanes = 0
        var livePanes = 0
        var runningPanes = 0

        for session in terminalSessions {
            guard let sessionId = session.id else {
                expectedPanes += 1
                continue
            }

            var paneIds = paneIDs(for: session)
            if paneIds.isEmpty {
                paneIds = TerminalRuntimeStore.shared.paneIds(for: sessionId)
            }

            let uniquePaneIds = Array(Set(paneIds))
            if uniquePaneIds.isEmpty {
                expectedPanes += 1
                continue
            }

            expectedPanes += uniquePaneIds.count
            let runtimeCounts = TerminalRuntimeStore.shared.runtimeCounts(for: sessionId, paneIds: uniquePaneIds)
            livePanes += runtimeCounts.livePanes
            runningPanes += runtimeCounts.runningPanes
        }

        return ActiveWorktreesTerminalRuntimeSnapshot(
            expectedPanes: expectedPanes,
            livePanes: livePanes,
            runningPanes: runningPanes
        )
    }

    private func paneIDs(for session: TerminalSession) -> [String] {
        if let layoutJSON = session.splitLayout,
           let layout = SplitLayoutHelper.decode(layoutJSON) {
            return layout.allPaneIds()
        }

        if let focusedPaneId = session.focusedPaneId,
           !focusedPaneId.isEmpty {
            return [focusedPaneId]
        }

        return []
    }
}
