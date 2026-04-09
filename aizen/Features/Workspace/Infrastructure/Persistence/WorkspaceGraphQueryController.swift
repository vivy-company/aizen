//
//  WorkspaceGraphQueryController.swift
//  aizen
//
//  Read-side controller for the workspace/repository/worktree graph used by navigation-heavy UI.
//

import Combine
import CoreData
import Foundation

@MainActor
final class WorkspaceGraphQueryController: ObservableObject {
    @Published private(set) var workspaces: [Workspace] = []
    @Published private(set) var repositories: [Repository] = []
    @Published private(set) var worktrees: [Worktree] = []

    let viewContext: NSManagedObjectContext
    private var cancellables = Set<AnyCancellable>()

    init(viewContext: NSManagedObjectContext) {
        self.viewContext = viewContext
        reload()
        observeGraphChanges()
    }

    func reload() {
        workspaces = fetchWorkspaces()
        repositories = fetchRepositories()
        worktrees = fetchWorktrees()
    }

    func workspace(id: UUID) -> Workspace? {
        workspaces.first { $0.id == id && !$0.isDeleted }
    }

    func repository(id: UUID) -> Repository? {
        repositories.first { $0.id == id && !$0.isDeleted }
    }

    func repository(path: String) -> Repository? {
        repositories.first { repository in
            guard !repository.isDeleted else { return false }
            return repository.path == path
        }
    }

    func worktree(id: UUID) -> Worktree? {
        worktrees.first { $0.id == id && !$0.isDeleted }
    }

    func repositories(in workspace: Workspace) -> [Repository] {
        repositories.filter { repository in
            guard !repository.isDeleted else { return false }
            return repository.workspace?.objectID == workspace.objectID
        }
    }

    func visibleRepositories(in workspace: Workspace, crossProjectMarker: String) -> [Repository] {
        repositories(in: workspace).filter { repository in
            !isCrossProjectRepository(repository, marker: crossProjectMarker)
        }
    }

    func worktrees(in repository: Repository) -> [Worktree] {
        worktrees
            .filter { worktree in
                guard !worktree.isDeleted else { return false }
                return worktree.repository?.objectID == repository.objectID
            }
            .sorted(by: worktreeSort(lhs:rhs:))
    }

    func workspaceWorktrees(in workspace: Workspace) -> [Worktree] {
        let repositoryIDs = Set(repositories(in: workspace).map(\.objectID))
        return worktrees
            .filter { worktree in
                guard !worktree.isDeleted else { return false }
                guard let repositoryID = worktree.repository?.objectID else { return false }
                return repositoryIDs.contains(repositoryID)
            }
            .sorted(by: worktreeSort(lhs:rhs:))
    }

    func primaryOrFirstWorktree(in repository: Repository) -> Worktree? {
        let candidates = worktrees(in: repository)
        return candidates.first(where: { $0.isPrimary }) ?? candidates.first
    }

    func bestWorktree(in workspace: Workspace) -> Worktree? {
        workspaceWorktrees(in: workspace).first
    }

    func route(for chatSessionId: UUID) -> (workspaceId: UUID, repoId: UUID, worktreeId: UUID)? {
        for worktree in worktrees {
            guard let worktreeId = worktree.id,
                  let repository = worktree.repository,
                  let repoId = repository.id,
                  let workspace = repository.workspace,
                  let workspaceId = workspace.id else {
                continue
            }

            let sessions = (worktree.chatSessions as? Set<ChatSession>) ?? []
            if sessions.contains(where: { $0.id == chatSessionId && !$0.isDeleted }) {
                return (workspaceId, repoId, worktreeId)
            }
        }

        return nil
    }

    private func observeGraphChanges() {
        NotificationCenter.default.publisher(
            for: .NSManagedObjectContextObjectsDidChange,
            object: viewContext
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] notification in
            guard let self else { return }
            guard self.containsRelevantGraphChange(notification) else { return }
            self.reload()
        }
        .store(in: &cancellables)
    }

    private func containsRelevantGraphChange(_ notification: Notification) -> Bool {
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
            return objects?.contains(where: isRelevantGraphObject(_:)) ?? false
        }
    }

    private func isRelevantGraphObject(_ object: NSManagedObject) -> Bool {
        object is Workspace || object is Repository || object is Worktree
    }

    private func fetchWorkspaces() -> [Workspace] {
        let request: NSFetchRequest<Workspace> = Workspace.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Workspace.order, ascending: true)]

        do {
            return try viewContext.fetch(request).filter { !$0.isDeleted }
        } catch {
            return []
        }
    }

    private func fetchRepositories() -> [Repository] {
        let request: NSFetchRequest<Repository> = Repository.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \Repository.name, ascending: true),
            NSSortDescriptor(keyPath: \Repository.lastUpdated, ascending: false)
        ]
        request.relationshipKeyPathsForPrefetching = ["workspace"]

        do {
            return try viewContext.fetch(request).filter { !$0.isDeleted }
        } catch {
            return []
        }
    }

    private func fetchWorktrees() -> [Worktree] {
        let request: NSFetchRequest<Worktree> = Worktree.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \Worktree.lastAccessed, ascending: false),
            NSSortDescriptor(keyPath: \Worktree.branch, ascending: true)
        ]
        request.relationshipKeyPathsForPrefetching = ["repository", "repository.workspace"]

        do {
            return try viewContext.fetch(request).filter { !$0.isDeleted }
        } catch {
            return []
        }
    }

    private func isCrossProjectRepository(_ repository: Repository, marker: String) -> Bool {
        repository.isCrossProject || repository.note == marker
    }

    private func worktreeSort(lhs: Worktree, rhs: Worktree) -> Bool {
        if lhs.isPrimary != rhs.isPrimary {
            return lhs.isPrimary
        }

        let lhsDate = lhs.lastAccessed ?? .distantPast
        let rhsDate = rhs.lastAccessed ?? .distantPast
        if lhsDate != rhsDate {
            return lhsDate > rhsDate
        }

        return (lhs.branch ?? lhs.path ?? "").localizedCaseInsensitiveCompare(rhs.branch ?? rhs.path ?? "") == .orderedAscending
    }
}
