//
//  WorktreeSessionManager.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import ACP
import os.log
import SwiftUI

// NOTE: TmuxSessionManager lives outside Views; keep a lightweight reference here.
private let tmuxManager = TmuxSessionManager.shared

@MainActor
struct WorktreeSessionManager {
    let worktree: Worktree
    let viewModel: WorktreeViewModel
    let logger: Logger

    var chatSessions: [ChatSession] {
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

    var terminalSessions: [TerminalSession] {
        let sessions = (worktree.terminalSessions as? Set<TerminalSession>) ?? []
        return sessions
            .filter { !$0.isDeleted }
            .sorted { ($0.createdAt ?? Date()) < ($1.createdAt ?? Date()) }
    }

    func closeChatSession(_ session: ChatSession) {
        guard let context = worktree.managedObjectContext else { return }
        guard !session.isDeleted else { return }

        if let id = session.id {
            ChatSessionManager.shared.removeAgentSession(for: id)
        }

        if viewModel.selectedChatSessionId == session.id {
            if let index = chatSessions.firstIndex(where: { $0.id == session.id }) {
                if index > 0 {
                    viewModel.selectedChatSessionId = chatSessions[index - 1].id
                } else if chatSessions.count > 1 {
                    viewModel.selectedChatSessionId = chatSessions[index + 1].id
                } else {
                    viewModel.selectedChatSessionId = nil
                }
            }
        }
        
        // Keep session tied to this worktree and mark it archived so it can be resumed from history.
        session.archived = true
        
        do {
            try context.save()
        } catch {
            logger.error("Failed to close chat session: \(error.localizedDescription)")
        }
    }

    func closeTerminalSession(_ session: TerminalSession) {
        guard let context = worktree.managedObjectContext else { return }
        guard !session.isDeleted else { return }

        // Capture values before any mutations
        let sessionId = session.id
        let layoutJSON = session.splitLayout

        // Update selection first (before delete) to prevent accessing deleted object
        if viewModel.selectedTerminalSessionId == sessionId {
            let currentSessions = terminalSessions
            if let index = currentSessions.firstIndex(where: { $0.id == sessionId }) {
                if index > 0 {
                    viewModel.selectedTerminalSessionId = currentSessions[index - 1].id
                } else if currentSessions.count > 1 {
                    viewModel.selectedTerminalSessionId = currentSessions[index + 1].id
                } else {
                    viewModel.selectedTerminalSessionId = nil
                }
            }
        }

        // Clean up terminal views
        if let id = sessionId {
            TerminalSessionManager.shared.removeAllTerminals(for: id)
        }

        // Delete from Core Data
        context.delete(session)

        do {
            try context.save()
        } catch {
            logger.error("Failed to delete terminal session: \(error.localizedDescription)")
        }

        // Best effort: tear down any tmux sessions backing this terminal tab (after Core Data save)
        if let layoutJSON = layoutJSON,
           let layout = SplitLayoutHelper.decode(layoutJSON) {
            let paneIds = layout.allPaneIds()
            Task {
                for paneId in paneIds {
                    await tmuxManager.killSession(paneId: paneId)
                }
            }
        }
    }

    func createNewChatSession() {
        createNewChatSession(withAgent: nil)
    }

    func createNewChatSession(withAgent agentId: String?) {
        guard let context = worktree.managedObjectContext else { return }

        let session = ChatSession(context: context)
        session.id = UUID()
        let agent = agentId ?? AgentRouter().defaultAgent
        let displayName = AgentRegistry.shared.getMetadata(for: agent)?.name ?? agent.capitalized
        session.title = displayName
        session.agentName = agent
        session.archived = false
        session.createdAt = Date()
        session.worktree = worktree

        do {
            try context.save()
            viewModel.selectedChatSessionId = session.id
        } catch {
            logger.error("Failed to create chat session: \(error.localizedDescription)")
        }
    }

    func createNewTerminalSession() {
        createNewTerminalSession(withPreset: nil)
    }

    func createNewTerminalSession(withPreset preset: TerminalPreset?) {
        guard let context = worktree.managedObjectContext else { return }

        let terminalSessions = (worktree.terminalSessions as? Set<TerminalSession>) ?? []

        let session = TerminalSession(context: context)
        session.id = UUID()
        session.createdAt = Date()
        session.worktree = worktree
        let defaultPaneId = TerminalLayoutDefaults.paneId(sessionId: session.id, focusedPaneId: nil)
        session.focusedPaneId = defaultPaneId
        session.splitLayout = SplitLayoutHelper.encode(TerminalLayoutDefaults.defaultLayout(paneId: defaultPaneId))

        if let preset = preset {
            session.title = preset.name
            session.initialCommand = preset.command
        } else {
            session.title = String(localized: "worktree.session.terminalTitle \(terminalSessions.count + 1)")
        }

        do {
            try context.save()
            logger.info("Created new terminal session with ID: \(session.id?.uuidString ?? "nil")")
            DispatchQueue.main.async {
                viewModel.selectedTerminalSessionId = session.id
                logger.info("Set selectedTerminalSessionId to: \(session.id?.uuidString ?? "nil")")
            }
        } catch {
            logger.error("Failed to create terminal session: \(error.localizedDescription)")
        }
    }
}
