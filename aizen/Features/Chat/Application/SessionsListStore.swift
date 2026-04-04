//
//  SessionsListStore.swift
//  aizen
//
//  ViewModel for managing the sessions list view
//  Single Responsibility: Session listing, filtering, and navigation logic
//

import ACP
import Combine
import CoreData
import Foundation
import os.log

@MainActor
final class SessionsListStore: ObservableObject {
    private static let pageSize = 10

    @Published var selectedFilter: SessionFilter = .active
    @Published var searchText: String = ""
    @Published var selectedWorktreeId: UUID?
    @Published var selectedAgentName: String?
    @Published var availableAgents: [String] = []
    @Published var errorMessage: String?
    @Published var fetchLimit: Int = SessionsListStore.pageSize
    @Published var sessions: [ChatSession] = []
    @Published var isLoading: Bool = false
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "win.aizen.app", category: "SessionsList")
    nonisolated static let unknownAgentLabel = "Unknown Agent"
    
    init(worktreeId: UUID? = nil) {
        self.selectedWorktreeId = worktreeId
    }
    
    func loadMore() {
        fetchLimit += Self.pageSize
    }

    func loadMoreIfNeeded(for session: ChatSession) {
        guard !isLoading else { return }
        guard sessions.count >= fetchLimit else { return }
        guard session.objectID == sessions.last?.objectID else { return }
        loadMore()
    }

    func reloadSessions(in context: NSManagedObjectContext) async {
        let filter = selectedFilter
        let search = searchText
        let worktreeId = selectedWorktreeId
        let agentName = selectedAgentName
        let limit = fetchLimit
        let unknownAgentLabel = Self.unknownAgentLabel
        isLoading = true
        defer { isLoading = false }
        do {
            let results = try await context.perform {
                let request = Self.buildFetchRequest(
                    filter: filter,
                    searchText: search,
                    worktreeId: worktreeId,
                    fetchLimit: limit,
                    agentName: agentName
                )
                return try context.fetch(request)
            }
            sessions = results
            let agents = try await context.perform {
                let request = Self.buildAgentNamesRequest(
                    filter: filter,
                    worktreeId: worktreeId
                )
                let results = try context.fetch(request)
                var names = Set<String>()
                var hasUnknown = false

                for item in results {
                    if let name = item["agentName"] as? String {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.isEmpty {
                            hasUnknown = true
                        } else {
                            names.insert(trimmed)
                        }
                    } else {
                        hasUnknown = true
                    }
                }

                var ordered = Array(names).sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending })
                if hasUnknown {
                    ordered.append(unknownAgentLabel)
                }
                return ordered
            }
            availableAgents = agents

            if let selected = selectedAgentName, selected == unknownAgentLabel {
                if !availableAgents.contains(unknownAgentLabel) {
                    selectedAgentName = nil
                }
            } else if let selected = selectedAgentName, !availableAgents.contains(selected) {
                selectedAgentName = nil
            }
        } catch {
            logger.error("Failed to fetch sessions: \(error.localizedDescription)")
            errorMessage = "Failed to load sessions: \(error.localizedDescription)"
        }
    }
    
    enum SessionFilter: String, CaseIterable {
        case all = "All"
        case active = "Active"
        case archived = "Archived"
    }
    
    func archiveSession(_ chatSession: ChatSession, context: NSManagedObjectContext) {
        guard let sessionId = chatSession.id else {
            logger.error("Cannot archive session without ID")
            errorMessage = "Invalid session"
            return
        }
        
        Task { @MainActor in
            do {
                try await ChatSessionPersistence.shared.archiveSession(sessionId, in: context)
                logger.info("Archived session \(sessionId.uuidString)")
            } catch {
                logger.error("Failed to archive session: \(error.localizedDescription)")
                errorMessage = "Failed to archive session: \(error.localizedDescription)"
            }
        }
    }
    
    func unarchiveSession(_ chatSession: ChatSession, context: NSManagedObjectContext) {
        guard let sessionId = chatSession.id else {
            logger.error("Cannot unarchive session without ID")
            errorMessage = "Invalid session"
            return
        }
        
        Task { @MainActor in
            do {
                try await ChatSessionPersistence.shared.unarchiveSession(sessionId, in: context)
                logger.info("Unarchived session \(sessionId.uuidString)")
            } catch {
                logger.error("Failed to unarchive session: \(error.localizedDescription)")
                errorMessage = "Failed to unarchive session: \(error.localizedDescription)"
            }
        }
    }
    
    func deleteSession(_ chatSession: ChatSession, context: NSManagedObjectContext) {
        context.delete(chatSession)
        
        do {
            try context.save()
            logger.info("Deleted session")
        } catch {
            logger.error("Failed to delete session: \(error.localizedDescription)")
            errorMessage = "Failed to delete session: \(error.localizedDescription)"
        }
    }
    
    func resumeSession(_ chatSession: ChatSession) {
        guard let chatSessionId = chatSession.id else {
            errorMessage = "Invalid session ID"
            logger.error("Session has no ID")
            return
        }
        
        if chatSession.archived {
            chatSession.archived = false
            do {
                try chatSession.managedObjectContext?.save()
                chatSession.managedObjectContext?.refresh(chatSession, mergeChanges: false)
                logger.info("Unarchived session \(chatSessionId.uuidString) for resume")
            } catch {
                errorMessage = "Failed to resume session: \(error.localizedDescription)"
                logger.error("Failed to save after unarchiving: \(error.localizedDescription)")
                return
            }
        }
        
        guard let worktree = chatSession.worktree, !worktree.isDeleted else {
            errorMessage = "Cannot resume session: environment has been deleted"
            logger.error("Worktree is deleted")
            return
        }
        
        guard let worktreeId = worktree.id else {
            errorMessage = "Invalid environment"
            logger.error("Worktree has no ID")
            return
        }
        
        guard let worktreePath = worktree.path else {
            errorMessage = "Cannot resume session: environment has no path"
            logger.error("Worktree has no path")
            return
        }
        
        guard FileManager.default.fileExists(atPath: worktreePath) else {
            errorMessage = "Cannot resume session: environment path no longer exists"
            logger.error("Worktree path does not exist: \(worktreePath)")
            return
        }
        
        NotificationCenter.default.post(
            name: .resumeChatSession,
            object: nil,
            userInfo: [
                "chatSessionId": chatSessionId,
                "worktreeId": worktreeId
            ]
        )
        
        logger.info("Requested resume for session \(chatSessionId.uuidString)")
    }
}

extension Notification.Name {
    static let resumeChatSession = Notification.Name("resumeChatSession")
}
