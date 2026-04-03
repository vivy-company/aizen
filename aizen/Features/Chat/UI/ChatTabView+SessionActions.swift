import AppKit
import Foundation
import os

extension ChatTabView {
    func syncSelectionAndCache() {
        if selectedSessionId == nil {
            selectedSessionId = sessions.last?.id
        } else if let currentId = selectedSessionId,
                  !sessions.contains(where: { $0.id == currentId }) {
            selectedSessionId = sessions.last?.id
        }
        pruneCache()
        updateCacheForSelection()
    }

    func updateCacheForSelection() {
        guard let selectedId = selectedSessionId else { return }
        guard sessions.contains(where: { $0.id == selectedId }) else { return }
        cachedSessionIds.removeAll { $0 == selectedId }
        cachedSessionIds.append(selectedId)
        if cachedSessionIds.count > maxCachedSessions {
            cachedSessionIds.removeFirst(cachedSessionIds.count - maxCachedSessions)
        }
    }

    func pruneCache() {
        let validIds = Set(sessions.compactMap { $0.id })
        cachedSessionIds.removeAll { !validIds.contains($0) }
    }

    func loadEnabledAgents() {
        Task {
            enabledAgents = AgentRegistry.shared.getEnabledAgents()
        }
    }

    func resumeRecentSession(_ session: ChatSession) {
        guard let sessionId = session.id else { return }
        guard session.worktree?.id == worktree.id else { return }

        if session.archived {
            session.archived = false
            do {
                try viewContext.save()
                viewContext.refresh(session, mergeChanges: false)
            } catch {
                logger.error("Failed to unarchive session: \(error.localizedDescription)")
                return
            }
        }

        guard let worktree = session.worktree, !worktree.isDeleted else { return }
        guard let worktreeId = worktree.id else { return }
        guard let worktreePath = worktree.path, FileManager.default.fileExists(atPath: worktreePath) else { return }

        NotificationCenter.default.post(
            name: .resumeChatSession,
            object: nil,
            userInfo: [
                "chatSessionId": sessionId,
                "worktreeId": worktreeId
            ]
        )
    }

    func createNewSession(withAgent agent: String) {
        guard let context = worktree.managedObjectContext else { return }

        let session = ChatSession(context: context)
        session.id = UUID()
        session.agentName = agent
        session.archived = false
        session.createdAt = Date()
        session.worktree = worktree

        let displayName = AgentRegistry.shared.getMetadata(for: agent)?.name ?? agent.capitalized
        session.title = displayName

        do {
            try context.save()
            selectedSessionId = session.id
            logger.info("Created new chat session: \(session.id?.uuidString ?? "unknown")")
        } catch {
            logger.error("Failed to create chat session: \(error.localizedDescription)")
        }
    }
}
