//
//  SessionsListViewModel.swift
//  aizen
//
//  ViewModel for managing the sessions list view
//  Single Responsibility: Session listing, filtering, and navigation logic
//

import Foundation
import CoreData
import Combine
import os.log

@MainActor
final class SessionsListViewModel: ObservableObject {
    @Published var selectedFilter: SessionFilter = .active
    @Published var searchText: String = ""
    @Published var selectedWorktreeId: UUID?
    @Published var errorMessage: String?
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "win.aizen.app", category: "SessionsList")
    
    enum SessionFilter: String, CaseIterable {
        case all = "All"
        case active = "Active"
        case archived = "Archived"
        
        var predicate: NSPredicate? {
            switch self {
            case .all:
                return nil
            case .active:
                return NSPredicate(format: "archived == NO")
            case .archived:
                return NSPredicate(format: "archived == YES")
            }
        }
    }
    
    func buildFetchRequest() -> NSFetchRequest<ChatSession> {
        let request: NSFetchRequest<ChatSession> = ChatSession.fetchRequest()
        
        var predicates: [NSPredicate] = []
        
        if let filterPredicate = selectedFilter.predicate {
            predicates.append(filterPredicate)
        }
        
        if let worktreeId = selectedWorktreeId {
            predicates.append(NSPredicate(format: "worktree.id == %@", worktreeId as CVarArg))
        }
        
        if !searchText.isEmpty {
            let searchPredicate = NSPredicate(
                format: "title CONTAINS[cd] %@ OR agentName CONTAINS[cd] %@",
                searchText, searchText
            )
            predicates.append(searchPredicate)
        }
        
        if !predicates.isEmpty {
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        }
        
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \ChatSession.lastMessageAt, ascending: false)
        ]
        
        request.relationshipKeyPathsForPrefetching = ["worktree"]
        request.fetchBatchSize = 50
        request.fetchLimit = 200
        
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
        guard let worktreeId = chatSession.worktree?.id else {
            errorMessage = "Cannot resume session: no associated worktree"
            logger.error("Session has no worktree relationship")
            return
        }
        
        guard let chatSessionId = chatSession.id else {
            errorMessage = "Cannot resume session: invalid session ID"
            logger.error("Session has no ID")
            return
        }
        
        guard let worktree = chatSession.worktree, !worktree.isDeleted else {
            errorMessage = "Cannot resume session: worktree has been deleted"
            logger.error("Worktree is deleted")
            return
        }
        
        guard let worktreePath = worktree.path else {
            errorMessage = "Cannot resume session: worktree has no path"
            logger.error("Worktree has no path")
            return
        }
        
        guard FileManager.default.fileExists(atPath: worktreePath) else {
            errorMessage = "Cannot resume session: worktree path no longer exists"
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
