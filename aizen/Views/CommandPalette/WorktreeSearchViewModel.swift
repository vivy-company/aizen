//
//  WorktreeSearchViewModel.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 20.12.25.
//

import Foundation
import Combine
import CoreData

@MainActor
final class WorktreeSearchViewModel: ObservableObject {
    @Published var searchQuery = ""
    @Published var results: [Worktree] = []
    @Published var selectedIndex = 0

    private var allWorktrees: [Worktree] = []
    private var currentWorktreeId: String?
    private var cancellables = Set<AnyCancellable>()
    private var searchTask: Task<Void, Never>?

    init() {
        setupSearchDebounce()
    }

    func updateSnapshot(_ worktrees: [Worktree], currentWorktreeId: String?) {
        allWorktrees = worktrees
        self.currentWorktreeId = currentWorktreeId
        performSearch()
    }

    private func setupSearchDebounce() {
        $searchQuery
            .debounce(for: .milliseconds(120), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.performSearch()
            }
            .store(in: &cancellables)
    }

    func performSearch() {
        searchTask?.cancel()
        let query = searchQuery
        let snapshot = allWorktrees
        let currentId = currentWorktreeId

        searchTask = Task { [weak self] in
            guard let self else { return }

            let filtered = self.filterWorktrees(snapshot, query: query, currentWorktreeId: currentId)
            guard !Task.isCancelled else { return }
            guard query == self.searchQuery else { return }

            self.results = filtered
            self.selectedIndex = 0
        }
    }

    func moveSelectionUp() {
        if selectedIndex > 0 {
            selectedIndex -= 1
        }
    }

    func moveSelectionDown() {
        if selectedIndex < results.count - 1 {
            selectedIndex += 1
        }
    }

    func getSelectedResult() -> Worktree? {
        guard selectedIndex < results.count else { return nil }
        return results[selectedIndex]
    }

    private func filterWorktrees(
        _ worktrees: [Worktree],
        query: String,
        currentWorktreeId: String?
    ) -> [Worktree] {
        let tokens = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
            .map { String($0).lowercased() }

        let base = worktrees.filter { worktree in
            guard !worktree.isDeleted else { return false }
            guard worktree.repository?.workspace != nil else { return false }
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
}
