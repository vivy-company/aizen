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
        isLoading = true
        defer { isLoading = false }
        do {
            let results = try await context.perform {
                let request = Self.buildFetchRequest(
                    filter: filter,
                    searchText: search,
                    worktreeId: worktreeId,
                    workspaceId: workspaceId,
                    fetchLimit: limit,
                    agentName: agentName
                )
                return try context.fetch(request)
            }
            sessions = results
            let agents = try await context.perform {
                let request = Self.buildAgentNamesRequest(
                    filter: filter,
                    worktreeId: worktreeId,
                    workspaceId: workspaceId
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
    
    func buildFetchRequest() -> NSFetchRequest<ChatSession> {
        Self.buildFetchRequest(
            filter: selectedFilter,
            searchText: searchText,
            worktreeId: selectedWorktreeId,
            workspaceId: selectedWorkspaceId,
            fetchLimit: fetchLimit,
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
            let workspacePredicate = NSPredicate(format: "worktree.repository.workspace.id == %@", workspaceId as CVarArg)
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

    nonisolated static func buildAgentNamesRequest(
        filter: SessionFilter,
        worktreeId: UUID?,
        workspaceId: UUID?
    ) -> NSFetchRequest<NSDictionary> {
        let request = NSFetchRequest<NSDictionary>(entityName: "ChatSession")
        request.resultType = .dictionaryResultType
        request.propertiesToFetch = ["agentName"]
        request.returnsDistinctResults = true

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
            let workspacePredicate = NSPredicate(format: "worktree.repository.workspace.id == %@", workspaceId as CVarArg)
            predicates.append(workspacePredicate)
        } else if let worktreeId = worktreeId {
            let worktreePredicate = NSPredicate(format: "worktree.id == %@ OR worktree == nil", worktreeId as CVarArg)
            predicates.append(worktreePredicate)
        }

        if !predicates.isEmpty {
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        }

        request.sortDescriptors = [
            NSSortDescriptor(key: "agentName", ascending: true)
        ]

        return request
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
