//
//  SessionsListViewModel.swift
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
final class SessionsListViewModel: ObservableObject {
    private static let pageSize = 10

    @Published var selectedFilter: SessionFilter = .active
    @Published var searchText: String = ""
    @Published var selectedWorktreeId: UUID?
    @Published var selectedWorkspaceId: UUID?
    @Published var selectedAgentName: String?
    @Published var availableAgents: [String] = []
    @Published var errorMessage: String?
    @Published var fetchLimit: Int = SessionsListViewModel.pageSize
    @Published var sessions: [ChatSession] = []
    @Published var isLoading: Bool = false
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "win.aizen.app", category: "SessionsList")
    nonisolated static let unknownAgentLabel = "Unknown Agent"
    
    init(worktreeId: UUID? = nil, workspaceId: UUID? = nil) {
        self.selectedWorktreeId = worktreeId
        self.selectedWorkspaceId = workspaceId
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
        let workspaceId = selectedWorkspaceId
        let agentName = selectedAgentName
        let limit = fetchLimit
        let unknownAgentLabel = Self.unknownAgentLabel
        let scopeSnapshot = ChatSessionScopeStore.shared.snapshot()
        isLoading = true
        defer { isLoading = false }
        do {
            let needsDetachedScopeFiltering = Self.requiresDetachedScopeFiltering(
                worktreeId: worktreeId,
                workspaceId: workspaceId
            )

            let results = try await context.perform {
                let request = Self.buildFetchRequest(
                    filter: filter,
                    searchText: search,
                    worktreeId: worktreeId,
                    workspaceId: workspaceId,
                    fetchLimit: needsDetachedScopeFiltering ? 0 : limit,
                    agentName: agentName
                )
                return try context.fetch(request)
            }
            sessions = Array(
                Self.applyDetachedScopeFilter(
                    to: results,
                    worktreeId: worktreeId,
                    workspaceId: workspaceId,
                    scopeSnapshot: scopeSnapshot
                ).prefix(limit)
            )

            let agents = try await context.perform {
                let request = Self.buildFetchRequest(
                    filter: filter,
                    searchText: "",
                    worktreeId: worktreeId,
                    workspaceId: workspaceId,
                    fetchLimit: 0,
                    agentName: nil
                )
                return try context.fetch(request)
            }
            availableAgents = Self.extractAgentNames(
                from: Self.applyDetachedScopeFilter(
                    to: agents,
                    worktreeId: worktreeId,
                    workspaceId: workspaceId,
                    scopeSnapshot: scopeSnapshot
                ),
                unknownAgentLabel: unknownAgentLabel
            )

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
    
    func buildFetchRequest() -> NSFetchRequest<ChatSession> {
        let requestLimit = Self.requiresDetachedScopeFiltering(
            worktreeId: selectedWorktreeId,
            workspaceId: selectedWorkspaceId
        ) ? 0 : fetchLimit

        return Self.buildFetchRequest(
            filter: selectedFilter,
            searchText: searchText,
            worktreeId: selectedWorktreeId,
            workspaceId: selectedWorkspaceId,
            fetchLimit: requestLimit,
            agentName: selectedAgentName
        )
    }

    nonisolated static func buildFetchRequest(
        filter: SessionFilter,
        searchText: String,
        worktreeId: UUID?,
        workspaceId: UUID?,
        fetchLimit: Int,
        agentName: String?
    ) -> NSFetchRequest<ChatSession> {
        let request = NSFetchRequest<ChatSession>(entityName: "ChatSession")
        
        var predicates: [NSPredicate] = []

        // Only include sessions with at least one user message
        predicates.append(NSPredicate(format: "SUBQUERY(messages, $m, $m.role == 'user').@count > 0"))
        
        switch filter {
        case .all:
            break
        case .active:
            predicates.append(NSPredicate(format: "archived == NO"))
        case .archived:
            predicates.append(NSPredicate(format: "archived == YES"))
        }
        
        if let workspaceId = workspaceId {
            let workspacePredicate = NSPredicate(
                format: "worktree.repository.workspace.id == %@ OR worktree == nil",
                workspaceId as CVarArg
            )
            predicates.append(workspacePredicate)
        } else if let worktreeId = worktreeId {
            // Show sessions for this worktree AND closed sessions (worktree == nil)
            let worktreePredicate = NSPredicate(format: "worktree.id == %@ OR worktree == nil", worktreeId as CVarArg)
            predicates.append(worktreePredicate)
        }
        
        if !searchText.isEmpty {
            let searchPredicate = NSPredicate(
                format: "title CONTAINS[cd] %@ OR agentName CONTAINS[cd] %@",
                searchText, searchText
            )
            predicates.append(searchPredicate)
        }

        if let agentName = agentName {
            if agentName == Self.unknownAgentLabel {
                predicates.append(NSPredicate(format: "agentName == nil OR agentName == ''"))
            } else {
                predicates.append(NSPredicate(format: "agentName == %@", agentName))
            }
        }
        
        if !predicates.isEmpty {
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        }
        
        request.sortDescriptors = [
            NSSortDescriptor(key: "lastMessageAt", ascending: false)
        ]
        
        request.relationshipKeyPathsForPrefetching = ["worktree"]
        request.fetchBatchSize = 10
        request.fetchLimit = fetchLimit
        
        return request
    }

    static func requiresDetachedScopeFiltering(worktreeId: UUID?, workspaceId: UUID?) -> Bool {
        workspaceId != nil || worktreeId != nil
    }

    static func applyDetachedScopeFilter(
        to sessions: [ChatSession],
        worktreeId: UUID?,
        workspaceId: UUID?,
        scopeSnapshot: ChatSessionScopeStore.Snapshot
    ) -> [ChatSession] {
        guard requiresDetachedScopeFiltering(worktreeId: worktreeId, workspaceId: workspaceId) else {
            return sessions
        }

        return sessions.filter { session in
            if let sessionWorktree = session.worktree, !sessionWorktree.isDeleted {
                if let workspaceId {
                    return sessionWorktree.repository?.workspace?.id == workspaceId
                }
                if let worktreeId {
                    return sessionWorktree.id == worktreeId
                }
                return true
            }

            guard let sessionId = session.id else { return false }
            if let workspaceId {
                return scopeSnapshot.workspaceId(for: sessionId) == workspaceId
            }
            if let worktreeId {
                return scopeSnapshot.worktreeId(for: sessionId) == worktreeId
            }
            return false
        }
    }

    static func extractAgentNames(
        from sessions: [ChatSession],
        unknownAgentLabel: String
    ) -> [String] {
        var names = Set<String>()
        var hasUnknown = false

        for session in sessions {
            if let name = session.agentName {
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
    
    func archiveSession(_ chatSession: ChatSession, context: NSManagedObjectContext) {
        guard let sessionId = chatSession.id else {
            logger.error("Cannot archive session without ID")
            errorMessage = "Invalid session"
            return
        }
        
        Task { @MainActor in
            do {
                try await SessionPersistenceService.shared.archiveSession(sessionId, in: context)
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
                try await SessionPersistenceService.shared.unarchiveSession(sessionId, in: context)
                logger.info("Unarchived session \(sessionId.uuidString)")
            } catch {
                logger.error("Failed to unarchive session: \(error.localizedDescription)")
                errorMessage = "Failed to unarchive session: \(error.localizedDescription)"
            }
        }
    }
    
    func deleteSession(_ chatSession: ChatSession, context: NSManagedObjectContext) {
        let sessionId = chatSession.id
        context.delete(chatSession)
        
        do {
            try context.save()
            if let sessionId {
                ChatSessionScopeStore.shared.clearScope(sessionId: sessionId)
            }
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
        
        // If session is closed (worktree == nil), reattach to current worktree
        if chatSession.worktree == nil {
            guard let currentWorktreeId = selectedWorktreeId else {
                errorMessage = "Open session history from an environment to resume closed sessions"
                logger.error("Cannot resume closed session without worktree context")
                return
            }
            
            let fetchRequest: NSFetchRequest<Worktree> = Worktree.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", currentWorktreeId as CVarArg)
            
            guard let worktree = try? chatSession.managedObjectContext?.fetch(fetchRequest).first else {
                errorMessage = "Cannot find environment"
                logger.error("Worktree not found for id: \(currentWorktreeId)")
                return
            }
            
            // Reattach session to current worktree
            chatSession.worktree = worktree
            do {
                try chatSession.managedObjectContext?.save()
                ChatSessionScopeStore.shared.clearScope(sessionId: chatSessionId)
                chatSession.managedObjectContext?.refresh(chatSession, mergeChanges: false)
                logger.info("Reattached closed session \(chatSessionId.uuidString) to environment \(worktree.id?.uuidString ?? "nil")")
            } catch {
                errorMessage = "Failed to reattach session: \(error.localizedDescription)"
                logger.error("Failed to save after reattaching: \(error.localizedDescription)")
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
