//
//  WorktreeSessionManager.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import SwiftUI
import os.log

@MainActor
struct WorktreeSessionManager {
    let worktree: Worktree
    let viewModel: WorktreeViewModel
    let logger: Logger

    var chatSessions: [ChatSession] {
        let sessions = (worktree.chatSessions as? Set<ChatSession>) ?? []
        return sessions.sorted { ($0.createdAt ?? Date()) < ($1.createdAt ?? Date()) }
    }

    var terminalSessions: [TerminalSession] {
        let sessions = (worktree.terminalSessions as? Set<TerminalSession>) ?? []
        return sessions.sorted { ($0.createdAt ?? Date()) < ($1.createdAt ?? Date()) }
    }

    func closeChatSession(_ session: ChatSession) {
        guard let context = worktree.managedObjectContext else { return }

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

        context.delete(session)

        do {
            try context.save()
        } catch {
            logger.error("Failed to delete chat session: \(error.localizedDescription)")
        }
    }

    func closeTerminalSession(_ session: TerminalSession) {
        guard let context = worktree.managedObjectContext else { return }

        if let id = session.id {
            TerminalSessionManager.shared.removeAllTerminals(for: id)
        }

        if viewModel.selectedTerminalSessionId == session.id {
            if let index = terminalSessions.firstIndex(where: { $0.id == session.id }) {
                if index > 0 {
                    viewModel.selectedTerminalSessionId = terminalSessions[index - 1].id
                } else if terminalSessions.count > 1 {
                    viewModel.selectedTerminalSessionId = terminalSessions[index + 1].id
                } else {
                    viewModel.selectedTerminalSessionId = nil
                }
            }
        }

        context.delete(session)

        do {
            try context.save()
        } catch {
            logger.error("Failed to delete terminal session: \(error.localizedDescription)")
        }
    }

    func createNewChatSession() {
        guard let context = worktree.managedObjectContext else { return }

        let session = ChatSession(context: context)
        session.id = UUID()
        let defaultAgent = AgentRouter().defaultAgent
        let displayName = AgentRegistry.shared.getMetadata(for: defaultAgent)?.name ?? defaultAgent.capitalized
        session.title = displayName
        session.agentName = defaultAgent
        session.createdAt = Date()
        session.worktree = worktree

        do {
            try context.save()
            DispatchQueue.main.async {
                viewModel.selectedChatSessionId = session.id
            }
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
