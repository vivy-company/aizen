//
//  WorktreeSearchViewModel.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 20.12.25.
//

import Foundation
import Combine
import CoreData

enum CommandPaletteMode {
    case workspace
    case environmentGlobal
    case environmentCurrentProject
}

@MainActor
final class WorktreeSearchViewModel: ObservableObject {
    @Published var searchQuery = ""
    @Published var results: [Worktree] = []
    @Published var workspaceResults: [Workspace] = []
    @Published var selectedIndex = 0
    @Published var mode: CommandPaletteMode = .environmentGlobal

    private var allWorktrees: [Worktree] = []
    private var allWorkspaces: [Workspace] = []
    private var currentWorktreeId: String?
    private var currentRepositoryId: String?
    private var cancellables = Set<AnyCancellable>()
    private var searchTask: Task<Void, Never>?
    private var ignoreExplicitMode = false

    init(currentRepositoryId: String? = nil) {
        self.currentRepositoryId = currentRepositoryId
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

    func updateWorkspaceSnapshot(_ workspaces: [Workspace]) {
        allWorkspaces = workspaces
        performSearch()
    }

    private func setupSearchDebounce() {
        $searchQuery
            .debounce(for: .milliseconds(120), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.ignoreExplicitMode = false
                self?.performSearch()
            }
            .store(in: &cancellables)
    }

    func performSearch() {
        searchTask?.cancel()
        let query = searchQuery
        let worktreeSnapshot = allWorktrees
        let workspaceSnapshot = allWorkspaces
        let currentId = currentWorktreeId
        let repositoryId = currentRepositoryId
        let parsed = parseQuery(query, fallbackMode: mode)
        let effectiveMode = (parsed.isExplicit && !ignoreExplicitMode) ? parsed.mode : mode
        let scopedRepositoryId: String?
        if effectiveMode == .environmentCurrentProject {
            scopedRepositoryId = repositoryId
        } else {
            scopedRepositoryId = nil
        }

        if !ignoreExplicitMode,
           parsed.isExplicit,
           parsed.mode != mode {
            mode = parsed.mode
        }

        let normalizedMode: CommandPaletteMode
        if effectiveMode == .environmentCurrentProject && scopedRepositoryId == nil {
            normalizedMode = .environmentGlobal
        } else {
            normalizedMode = effectiveMode
        }

        if normalizedMode == .environmentGlobal {
            if !ignoreExplicitMode,
               effectiveMode != mode {
                mode = .environmentGlobal
            }
        }

        searchTask = Task { [weak self] in
            guard let self else { return }

            let environmentResults = self.filterWorktrees(
                worktreeSnapshot,
                query: parsed.query,
                currentWorktreeId: currentId,
                currentRepositoryId: scopedRepositoryId
            )
            let workspaceResults = self.filterWorkspaces(workspaceSnapshot, query: parsed.query)
            guard !Task.isCancelled else { return }
            guard query == self.searchQuery else { return }

            switch normalizedMode {
            case .environmentGlobal, .environmentCurrentProject:
                self.results = environmentResults
                self.workspaceResults = []
            case .workspace:
                self.results = []
                self.workspaceResults = workspaceResults
            }

            self.selectedIndex = 0
        }
    }

    func setMode(_ newMode: CommandPaletteMode) {
        if mode != newMode {
            mode = newMode
            ignoreExplicitMode = false
            performSearch()
        }
    }

    func toggleMode() {
        ignoreExplicitMode = true
        switch mode {
        case .environmentGlobal:
            mode = .workspace
        case .workspace:
            mode = .environmentCurrentProject
        case .environmentCurrentProject:
            mode = .environmentGlobal
        }
        performSearch()
    }

    func moveSelectionUp() {
        if selectedIndex > 0 {
            selectedIndex -= 1
        }
    }

    func moveSelectionDown() {
        let count = currentResultCount()
        if selectedIndex < count - 1 {
            selectedIndex += 1
        }
    }

    func getSelectedResult() -> Worktree? {
        guard mode == .environmentGlobal || mode == .environmentCurrentProject else { return nil }
        guard selectedIndex < results.count else { return nil }
        return results[selectedIndex]
    }

    func getSelectedWorkspaceResult() -> Workspace? {
        guard mode == .workspace else { return nil }
        guard selectedIndex < workspaceResults.count else { return nil }
        return workspaceResults[selectedIndex]
    }

    private func currentResultCount() -> Int {
        switch mode {
        case .environmentGlobal, .environmentCurrentProject:
            return results.count
        case .workspace:
            return workspaceResults.count
        }
    }

    private func parseQuery(
        _ query: String,
        fallbackMode: CommandPaletteMode
    ) -> (mode: CommandPaletteMode, query: String, isExplicit: Bool) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (fallbackMode, "", false) }

        let lower = trimmed.lowercased()

        let commandPairs: [(String, CommandPaletteMode)] = [
            ("workspace:", .workspace),
            ("workspace ", .workspace),
            ("w:", .workspace),
            ("w ", .workspace),
            ("ws:", .workspace),
            ("ws ", .workspace),
            ("environment:", .environmentGlobal),
            ("environment ", .environmentGlobal),
            ("env:", .environmentGlobal),
            ("env ", .environmentGlobal),
            ("e:", .environmentGlobal),
            ("e ", .environmentGlobal),
            ("project:", .environmentCurrentProject),
            ("project ", .environmentCurrentProject),
            ("repo:", .environmentCurrentProject),
            ("repo ", .environmentCurrentProject),
            ("current:", .environmentCurrentProject),
            ("current ", .environmentCurrentProject),
            ("local:", .environmentCurrentProject),
            ("local ", .environmentCurrentProject),
            ("cp:", .environmentCurrentProject),
            ("cp ", .environmentCurrentProject)
        ]

        for command in commandPairs {
            let (prefix, commandMode) = command
            if lower.hasPrefix(prefix) {
                let stripped = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                return (commandMode, stripped, true)
            }
        }

        return (fallbackMode, trimmed, false)
    }

    private func filterWorkspaces(_ workspaces: [Workspace], query: String) -> [Workspace] {
        let tokens = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
            .map { String($0).lowercased() }

        let base = workspaces.filter { workspace in
            guard workspace.id != nil else { return false }
            return true
        }

        let filtered: [Workspace]
        if tokens.isEmpty {
            filtered = base
        } else {
            filtered = base.filter { workspace in
                let fields = searchFields(for: workspace).map { $0.lowercased() }
                guard !fields.isEmpty else { return false }
                return tokens.allSatisfy { token in
                    fields.contains(where: { $0.localizedCaseInsensitiveContains(token) })
                }
            }
        }

        return filtered.sorted {
            let left = $0.name?.lowercased() ?? ""
            let right = $1.name?.lowercased() ?? ""
            if left != right {
                return left < right
            }
            return ($0.id?.uuidString ?? "") < ($1.id?.uuidString ?? "")
        }
    }

    private func filterWorktrees(
        _ worktrees: [Worktree],
        query: String,
        currentWorktreeId: String?,
        currentRepositoryId: String?
    ) -> [Worktree] {
        let tokens = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
            .map { String($0).lowercased() }

        let base = worktrees.filter { worktree in
            guard !worktree.isDeleted else { return false }
            guard worktree.repository?.workspace != nil else { return false }
            if let repositoryId = currentRepositoryId,
               let worktreeRepositoryId = worktree.repository?.id?.uuidString,
               repositoryId != worktreeRepositoryId {
                return false
            }
            if let currentId = currentWorktreeId,
               let worktreeId = worktree.id?.uuidString,
               currentId == worktreeId {
                return false
            }
            return true
        }

        let filtered: [Worktree]
        if tokens.isEmpty {
            filtered = base
        } else {
            filtered = base.filter { worktree in
                let fields = searchFields(for: worktree).map { $0.lowercased() }
                guard !fields.isEmpty else { return false }
                return tokens.allSatisfy { token in
                    fields.contains(where: { $0.localizedCaseInsensitiveContains(token) })
                }
            }
        }

        let sorted = filtered.sorted { a, b in
            let aLast = a.lastAccessed ?? .distantPast
            let bLast = b.lastAccessed ?? .distantPast
            if aLast != bLast { return aLast > bLast }
            return (a.branch ?? "") < (b.branch ?? "")
        }

        return Array(sorted.prefix(50))
    }

    private func searchFields(for worktree: Worktree) -> [String] {
        var fields: [String] = []

        if let branch = worktree.branch, !branch.isEmpty {
            fields.append(branch)
        }
        if let repoName = worktree.repository?.name, !repoName.isEmpty {
            fields.append(repoName)
        }
        if let workspaceName = worktree.repository?.workspace?.name, !workspaceName.isEmpty {
            fields.append(workspaceName)
        }
        if let note = worktree.note, !note.isEmpty {
            fields.append(note)
        }

        return fields
    }

    private func searchFields(for workspace: Workspace) -> [String] {
        var fields: [String] = []

        if let name = workspace.name, !name.isEmpty {
            fields.append(name)
        }

        return fields
    }
}
