//
//  WorktreeDetailStore.swift
//  aizen
//
//  Application store for worktree detail session selection
//

import ACP
import Combine
import CoreData
import Foundation
import SwiftUI

@MainActor
class WorktreeDetailStore: ObservableObject {
    @Published var selectedChatSessionId: UUID?
    @Published var selectedTerminalSessionId: UUID?
    @Published var selectedFileSessionId: UUID?
    @Published var selectedBrowserSessionId: UUID?
    @Published private(set) var chatSessions: [ChatSession] = []
    @Published private(set) var recentChatSessions: [ChatSession] = []
    @Published private(set) var terminalSessions: [TerminalSession] = []
    @Published private(set) var browserSessions: [BrowserSession] = []

    private let worktree: Worktree
    private let repositoryManager: WorkspaceRepositoryStore
    private var cancellables = Set<AnyCancellable>()

    init(worktree: Worktree, repositoryManager: WorkspaceRepositoryStore) {
        self.worktree = worktree
        self.repositoryManager = repositoryManager
        reloadSessionCollections()
        observeSessionCollections()
    }

    func reloadSessionCollections() {
        let snapshot = WorktreeSessionSnapshotBuilder.lists(for: worktree)
        chatSessions = snapshot.chatSessions
        recentChatSessions = WorktreeSessionSnapshotBuilder.recentChatSessions(for: worktree)
        terminalSessions = snapshot.terminalSessions
        browserSessions = snapshot.browserSessions
    }

    func containsChatSession(_ sessionId: UUID) -> Bool {
        chatSessions.contains { $0.id == sessionId }
    }

    func containsTerminalSession(_ sessionId: UUID) -> Bool {
        terminalSessions.contains { $0.id == sessionId }
    }

    func containsBrowserSession(_ sessionId: UUID) -> Bool {
        browserSessions.contains { $0.id == sessionId }
    }

    private func observeSessionCollections() {
        guard let context = worktree.managedObjectContext else { return }

        NotificationCenter.default.publisher(
            for: .NSManagedObjectContextObjectsDidChange,
            object: context
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] notification in
            guard let self else { return }
            guard self.containsRelevantSessionChange(notification) else { return }
            self.reloadSessionCollections()
        }
        .store(in: &cancellables)
    }

    private func containsRelevantSessionChange(_ notification: Notification) -> Bool {
        if notification.userInfo?[NSInvalidatedAllObjectsKey] != nil {
            return true
        }

        let relevantKeys = [
            NSInsertedObjectsKey,
            NSUpdatedObjectsKey,
            NSDeletedObjectsKey,
            NSRefreshedObjectsKey
        ]

        return relevantKeys.contains { key in
            let objects = notification.userInfo?[key] as? Set<NSManagedObject>
            return objects?.contains(where: isRelevantSessionObject(_:)) ?? false
        }
    }

    private func isRelevantSessionObject(_ object: NSManagedObject) -> Bool {
        if let changedWorktree = object as? Worktree {
            return changedWorktree.objectID == worktree.objectID
        }

        if object is ChatSession || object is TerminalSession || object is BrowserSession || object is FileBrowserSession {
            return belongsToCurrentWorktree(object)
        }

        return false
    }

    private func belongsToCurrentWorktree(_ object: NSManagedObject) -> Bool {
        if let relatedWorktree = object.value(forKey: "worktree") as? Worktree {
            return relatedWorktree.objectID == worktree.objectID
        }

        if let committedWorktree = object.committedValues(forKeys: ["worktree"])["worktree"] as? Worktree {
            return committedWorktree.objectID == worktree.objectID
        }

        return false
    }
}
