//
//  WorktreeSearchViewModel.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 20.12.25.
//

import Combine
import CoreData

@MainActor
final class WorktreeSearchViewModel: ObservableObject {
    @Published var searchQuery = ""
    @Published var selectedIndex = 0
    @Published var scope: CommandPaletteScope = .all
    @Published private(set) var sections: [CommandPaletteSection] = []

    private var allWorktrees: [Worktree] = []
    private var allWorkspaces: [Workspace] = []
    private var currentWorktreeId: String?
    private var currentRepositoryId: String?
    var currentWorkspaceId: String?
    private var cancellables = Set<AnyCancellable>()
    private var ignoreExplicitScope = false
    private var flattenedItems: [CommandPaletteItem] = []
    let crossProjectRepositoryMarker = "__aizen.cross_project.workspace_repo__"
    let defaults = UserDefaults.standard

    init(currentRepositoryId: String? = nil, currentWorkspaceId: String? = nil) {
        self.currentRepositoryId = currentRepositoryId
        self.currentWorkspaceId = currentWorkspaceId
        setupSearchDebounce()
    }

    func updateSnapshot(_ worktrees: [Worktree], currentWorktreeId: String?) {
        allWorktrees = worktrees
        self.currentWorktreeId = currentWorktreeId
        performSearch()
    }

    func updateCurrentRepository(_ repositoryId: String?) {
        if currentRepositoryId == repositoryId {
            return
        }
        currentRepositoryId = repositoryId
        performSearch()
    }

    func updateCurrentWorkspace(_ workspaceId: String?) {
        if currentWorkspaceId == workspaceId {
            return
        }
        currentWorkspaceId = workspaceId
        performSearch()
    }

    func updateWorkspaceSnapshot(_ workspaces: [Workspace]) {
        allWorkspaces = workspaces
        performSearch()
    }

    private func setupSearchDebounce() {
        $searchQuery
            .debounce(for: .milliseconds(120), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.ignoreExplicitScope = false
                self?.performSearch()
            }
            .store(in: &cancellables)
    }

    func performSearch() {
        let query = searchQuery
        let worktreeSnapshot = allWorktrees
        let workspaceSnapshot = allWorkspaces
        let currentWorktreeId = currentWorktreeId
        let currentRepositoryId = currentRepositoryId
        let currentWorkspaceId = currentWorkspaceId
        let parsed = CommandPaletteQueryParser.parse(query, fallbackScope: scope)
        let effectiveScope = (parsed.isExplicit && !ignoreExplicitScope) ? parsed.scope : scope

        if !ignoreExplicitScope,
           parsed.isExplicit,
           parsed.scope != scope {
            scope = parsed.scope
        }

        let resolved = buildSections(
            scope: effectiveScope,
            query: parsed.query,
            worktrees: worktreeSnapshot,
            workspaces: workspaceSnapshot,
            currentWorktreeId: currentWorktreeId,
            currentRepositoryId: currentRepositoryId,
            currentWorkspaceId: currentWorkspaceId
        )

        guard query == searchQuery else { return }

        sections = resolved
        flattenedItems = resolved.flatMap(\.items)
        selectedIndex = 0
    }

    func setScope(_ newScope: CommandPaletteScope, ignoreQueryPrefix: Bool = true) {
        if scope != newScope {
            scope = newScope
        }
        if ignoreQueryPrefix {
            ignoreExplicitScope = true
        }
        performSearch()
    }

    func cycleScopeForward() {
        ignoreExplicitScope = true
        switch scope {
        case .all:
            scope = .currentProject
        case .currentProject:
            scope = .workspace
        case .workspace:
            scope = .tabs
        case .tabs:
            scope = .all
        }
        performSearch()
    }

    func moveSelectionUp() {
        if selectedIndex > 0 {
            selectedIndex -= 1
        }
    }

    func moveSelectionDown() {
        if selectedIndex < flattenedItems.count - 1 {
            selectedIndex += 1
        }
    }

    func selectedItem() -> CommandPaletteItem? {
        guard selectedIndex >= 0, selectedIndex < flattenedItems.count else { return nil }
        return flattenedItems[selectedIndex]
    }

    func selectedNavigationAction() -> CommandPaletteNavigationAction? {
        guard let item = selectedItem(),
              let workspaceId = item.workspaceId,
              let repoId = item.repoId,
              let worktreeId = item.worktreeId else {
            return nil
        }

        switch item.kind {
        case .workspace, .worktree:
            return .worktree(workspaceId: workspaceId, repoId: repoId, worktreeId: worktreeId)
        case .tab:
            guard let tabId = item.tabId else { return nil }
            return .tab(workspaceId: workspaceId, repoId: repoId, worktreeId: worktreeId, tabId: tabId)
        case .chatSession:
            guard let sessionId = item.sessionId else { return nil }
            return .chatSession(
                workspaceId: workspaceId,
                repoId: repoId,
                worktreeId: worktreeId,
                sessionId: sessionId
            )
        case .terminalSession:
            guard let sessionId = item.sessionId else { return nil }
            return .terminalSession(
                workspaceId: workspaceId,
                repoId: repoId,
                worktreeId: worktreeId,
                sessionId: sessionId
            )
        case .browserSession:
            guard let sessionId = item.sessionId else { return nil }
            return .browserSession(
                workspaceId: workspaceId,
                repoId: repoId,
                worktreeId: worktreeId,
                sessionId: sessionId
            )
        }
    }

}
