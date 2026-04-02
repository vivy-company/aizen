//
//  FileSearchViewModel.swift
//  aizen
//
//  Created on 2025-11-19.
//

import Foundation
import SwiftUI
import Combine

@MainActor
class FileSearchViewModel: ObservableObject {
    @Published var searchQuery = ""
    @Published var results: [FileSearchResult] = []
    @Published var selectedIndex = 0
    @Published var isIndexing = false

    private let searchService = FileSearchService.shared
    private let worktreePath: String
    private var allResults: [FileSearchIndexResult] = []
    private var cancellables = Set<AnyCancellable>()
    private var searchTask: Task<Void, Never>?

    init(worktreePath: String) {
        self.worktreePath = worktreePath
        setupSearchDebounce()
    }

    private func setupSearchDebounce() {
        $searchQuery
            .debounce(for: .milliseconds(120), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.performSearch()
            }
            .store(in: &cancellables)
    }

    // Index files on appear
    func indexFiles() {
        guard !isIndexing else { return }

        isIndexing = true
        searchTask?.cancel()

        Task {
            do {
                allResults = try await searchService.indexDirectory(worktreePath)
                // Show recent files initially
                let initialResults = await searchService.search(
                    query: "",
                    in: allResults,
                    worktreePath: worktreePath,
                    limit: 50
                )
                results = mapToDisplayResults(initialResults)
                isIndexing = false
            } catch {
                print("Failed to index directory: \(error)")
                isIndexing = false
            }
        }
    }

    // Perform search (debouncing handled by Combine in init)
    func performSearch() {
        searchTask?.cancel()
        let query = searchQuery
        let snapshot = allResults
        let path = worktreePath

        searchTask = Task { [weak self] in
            guard let self else { return }
            let searchResults = await self.searchService.search(
                query: query,
                in: snapshot,
                worktreePath: path,
                limit: 50
            )

            guard !Task.isCancelled else { return }
            guard query == self.searchQuery else { return }
            self.results = self.mapToDisplayResults(searchResults)
            self.selectedIndex = 0
        }
    }

    // Navigate selection
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

    // Get selected result
    func getSelectedResult() -> FileSearchResult? {
        guard selectedIndex < results.count else { return nil }
        return results[selectedIndex]
    }

    // Track opened file
    func trackFileOpen(_ path: String) {
        Task {
            await searchService.addRecentFile(path, worktreePath: worktreePath)
        }
    }

    // Clear cache
    func clearCache() {
        Task {
            await searchService.clearCache(for: worktreePath)
        }
    }

    // MARK: - Helpers

    private func mapToDisplayResults(_ entries: [FileSearchIndexResult]) -> [FileSearchResult] {
        entries.compactMap { entry in
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: entry.path, isDirectory: &isDirectory) else {
                return nil
            }

            // Cmd+P is file search; hide directory/symlink-directory entries.
            guard !isDirectory.boolValue else {
                return nil
            }

            return FileSearchResult(
                path: entry.path,
                relativePath: entry.relativePath,
                isDirectory: false,
                matchScore: entry.matchScore
            )
        }
    }
}
