import CoreData
import Foundation
import os.log

extension ActiveWorktreesView {
    func navigate(to worktree: Worktree) {
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

    func terminateAll() {
        for worktree in activeWorktrees {
            terminateSessions(for: worktree)
        }
    }

    func terminateSessions(for worktree: Worktree) {
        let sessionLists = WorktreeSessionSnapshotBuilder.lists(for: worktree)

        for session in sessionLists.chatSessions {
            if let id = session.id {
                ChatSessionRegistry.shared.removeAgentSession(for: id)
            }
            viewContext.delete(session)
        }

        for session in sessionLists.terminalSessions {
            if let id = session.id {
                TerminalRuntimeStore.shared.removeAllTerminals(for: id)
            }

            if sessionPersistence,
               let layoutJSON = session.splitLayout,
               let layout = SplitLayoutHelper.decode(layoutJSON) {
                let paneIds = layout.allPaneIds()
                Task {
                    for paneId in paneIds {
                        await TmuxSessionRuntime.shared.killSession(paneId: paneId)
                    }
                }
            }

            viewContext.delete(session)
        }

        for session in sessionLists.browserSessions {
            viewContext.delete(session)
        }

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
