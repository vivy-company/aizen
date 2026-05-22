import Combine
import CryptoKit
import Foundation

@MainActor
final class ProjectSearchStore: ObservableObject {
    @Published var searchQuery = ""
    @Published var mode: ProjectSearchMode
    @Published var grepMode: ProjectSearchGrepMode
    @Published private(set) var results: [ProjectSearchResult] = []
    @Published private(set) var selectedIndex = 0
    @Published private(set) var selectedResultID: String?
    @Published private(set) var isSearching = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var status: ProjectSearchStatus = .idle
    @Published private(set) var previewState: ProjectSearchPreviewState
    @Published private(set) var totalMatched = 0
    @Published private(set) var regexFallbackError: String?
    @Published private(set) var nextFileOffset: Int?
    @Published private(set) var lastErrorMessage: String?

    let worktreePath: String

    private let searchService = ProjectSearchService.shared
    private var cancellables = Set<AnyCancellable>()
    private var searchTask: Task<Void, Never>?
    private var loadMoreTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var statusTask: Task<Void, Never>?
    private var hasAppeared = false
    private var searchRevision = 0

    init(worktreePath: String, initialMode: ProjectSearchMode = .files) {
        self.worktreePath = worktreePath
        self.mode = initialMode
        self.grepMode = Self.loadPersistedGrepMode(for: worktreePath)
        self.previewState = .idle(Self.previewPlaceholder(for: initialMode, query: ""))
        setupSearchObservers()
    }

    deinit {
        searchTask?.cancel()
        loadMoreTask?.cancel()
        previewTask?.cancel()
        statusTask?.cancel()
    }

    var selectedResult: ProjectSearchResult? {
        if let selectedResultID,
           let result = results.first(where: { $0.id == selectedResultID }) {
            return result
        }

        guard results.indices.contains(selectedIndex) else { return nil }
        return results[selectedIndex]
    }

    var canLoadMore: Bool {
        mode == .content &&
        nextFileOffset != nil &&
        !searchQueryTrimmed.isEmpty &&
        !isSearching &&
        !isLoadingMore
    }

    var resultsSummaryText: String {
        if isSearching && results.isEmpty {
            return mode == .files ? "Searching files" : "Searching contents"
        }

        if searchQueryTrimmed.isEmpty && mode == .files {
            if totalMatched > 0 {
                return totalMatched == 1 ? "1 file" : "\(totalMatched) files"
            }
            return "Project files"
        }

        if totalMatched > 0 {
            return totalMatched == 1 ? "1 match" : "\(totalMatched) matches"
        }

        if mode == .content && searchQueryTrimmed.isEmpty {
            return "Content search"
        }

        return "No matches"
    }

    var statusText: String? {
        if status.isScanning {
            return "Indexing \(status.scannedFilesCount) files"
        }
        if !status.isWarmupComplete {
            return "Warming search"
        }
        if !status.isWatcherReady {
            return "Starting file watcher"
        }
        return nil
    }

    var emptyStateTitle: String {
        if lastErrorMessage != nil {
            return "Search failed"
        }
        if mode == .content && searchQueryTrimmed.isEmpty {
            return "Search file contents"
        }
        if searchQueryTrimmed.isEmpty && mode == .files {
            return status.isScanning ? "Indexing project" : "No files found"
        }
        return "No matches found"
    }

    var emptyStateMessage: String {
        if let lastErrorMessage {
            return lastErrorMessage
        }
        if mode == .content && searchQueryTrimmed.isEmpty {
            return "Type a query to search file contents across the current worktree."
        }
        if searchQueryTrimmed.isEmpty && mode == .files {
            return status.isScanning
                ? "Results will appear as the repository scan completes."
                : "This worktree does not contain any searchable files."
        }
        return "Try a broader query or switch between file and content search."
    }

    var emptyStateSymbolName: String {
        if lastErrorMessage != nil {
            return "exclamationmark.triangle"
        }
        return mode == .content ? "text.page.badge.magnifyingglass" : "magnifyingglass"
    }

    func onAppear() {
        guard !hasAppeared else { return }
        hasAppeared = true
        persistGrepMode(grepMode)
        refreshStatus()
        Task { [weak self] in
            guard let self else { return }
            await self.searchService.refreshGitStatus(worktreePath: self.worktreePath)
        }
        refreshResults()
    }

    func activate(mode: ProjectSearchMode) {
        if self.mode == mode {
            if !hasAppeared {
                onAppear()
            }
            return
        }
        self.mode = mode
    }

    func switchMode() {
        mode = mode.toggled()
    }

    func moveSelectionUp() {
        guard selectedIndex > 0 else { return }
        setSelection(index: selectedIndex - 1)
    }

    func moveSelectionDown() {
        guard selectedIndex < results.count - 1 else { return }
        setSelection(index: selectedIndex + 1)
    }

    func selectResult(at index: Int) {
        guard results.indices.contains(index) else { return }
        guard selectedIndex != index || selectedResultID != results[index].id else { return }
        setSelection(index: index)
    }

    func selectResult(id: String) {
        guard let index = results.firstIndex(where: { $0.id == id }) else { return }
        selectResult(at: index)
    }

    func activateSelection() -> SearchOpenRequest? {
        guard let selectedResult else { return nil }
        let query = searchQueryTrimmed
        Task { [weak self] in
            guard let self else { return }
            await self.searchService.trackSelection(
                query: query,
                selectedPath: selectedResult.path,
                worktreePath: self.worktreePath
            )
        }
        return selectedResult.openRequest
    }

    func loadMore() {
        guard canLoadMore, let fileOffset = nextFileOffset else { return }

        let query = searchQueryTrimmed
        let grepMode = grepMode
        let selectedResultID = selectedResult?.id

        loadMoreTask?.cancel()
        isLoadingMore = true
        lastErrorMessage = nil

        loadMoreTask = Task { [weak self] in
            guard let self else { return }

            do {
                let response = try await self.searchService.searchContent(
                    query: query,
                    grepMode: grepMode,
                    worktreePath: self.worktreePath,
                    limit: 60,
                    fileOffset: fileOffset
                )

                guard !Task.isCancelled,
                      self.isCurrentContentLoad(query: query, grepMode: grepMode)
                else { return }

                let additionalResults = response.results.map(ProjectSearchResult.content)
                self.appendSearchResults(
                    additionalResults,
                    totalMatched: response.totalMatched,
                    nextFileOffset: response.nextFileOffset,
                    regexFallbackError: response.regexFallbackError,
                    status: response.status,
                    selectedResultID: selectedResultID
                )
            } catch {
                guard !Task.isCancelled,
                      self.isCurrentContentLoad(query: query, grepMode: grepMode)
                else { return }
                self.isLoadingMore = false
                self.lastErrorMessage = error.localizedDescription
            }
        }
    }

    private var searchQueryTrimmed: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func setupSearchObservers() {
        Publishers.CombineLatest3(
            $searchQuery.removeDuplicates(),
            $mode.removeDuplicates(),
            $grepMode.removeDuplicates()
        )
        .dropFirst()
        .debounce(for: .milliseconds(120), scheduler: DispatchQueue.main)
        .sink { [weak self] _, _, grepMode in
            guard let self else { return }
            self.persistGrepMode(grepMode)
            self.refreshResults()
        }
        .store(in: &cancellables)
    }

    private func refreshResults() {
        guard hasAppeared else { return }

        searchTask?.cancel()
        loadMoreTask?.cancel()
        previewTask?.cancel()
        isLoadingMore = false
        lastErrorMessage = nil
        searchRevision += 1

        let revision = searchRevision
        let query = searchQueryTrimmed
        let mode = mode
        let grepMode = grepMode

        if mode == .content && query.isEmpty {
            isSearching = false
            results = []
            setSelection(index: nil, updatePreview: false)
            totalMatched = 0
            regexFallbackError = nil
            nextFileOffset = nil
            previewState = .idle(Self.previewPlaceholder(for: mode, query: query))
            refreshStatus()
            return
        }

        isSearching = true
        regexFallbackError = nil
        nextFileOffset = nil
        if results.isEmpty {
            previewState = .loading
        }

        searchTask = Task { [weak self] in
            guard let self else { return }

            do {
                switch mode {
                case .files:
                    let response = try await self.searchService.searchFiles(
                        query: query,
                        worktreePath: self.worktreePath,
                        limit: 80
                    )

                    guard !Task.isCancelled,
                          self.isCurrentSearch(
                              revision: revision,
                              query: query,
                              mode: mode,
                              grepMode: grepMode
                          )
                    else { return }

                    self.applySearchResults(
                        response.results.map(ProjectSearchResult.file),
                        totalMatched: response.totalMatched,
                        nextFileOffset: nil,
                        regexFallbackError: nil,
                        status: response.status
                    )

                case .content:
                    let response = try await self.searchService.searchContent(
                        query: query,
                        grepMode: grepMode,
                        worktreePath: self.worktreePath,
                        limit: 60
                    )

                    guard !Task.isCancelled,
                          self.isCurrentSearch(
                              revision: revision,
                              query: query,
                              mode: mode,
                              grepMode: grepMode
                          )
                    else { return }

                    self.applySearchResults(
                        response.results.map(ProjectSearchResult.content),
                        totalMatched: response.totalMatched,
                        nextFileOffset: response.nextFileOffset,
                        regexFallbackError: response.regexFallbackError,
                        status: response.status
                    )
                }
            } catch {
                guard !Task.isCancelled,
                      self.isCurrentSearch(
                          revision: revision,
                          query: query,
                          mode: mode,
                          grepMode: grepMode
                      )
                else { return }
                self.isSearching = false
                self.results = []
                self.setSelection(index: nil, updatePreview: false)
                self.totalMatched = 0
                self.regexFallbackError = nil
                self.nextFileOffset = nil
                self.lastErrorMessage = error.localizedDescription
                self.previewState = .unavailable("Unable to complete project search.")
                self.refreshStatus()
            }
        }
    }

    private func applySearchResults(
        _ newResults: [ProjectSearchResult],
        totalMatched: Int,
        nextFileOffset: Int?,
        regexFallbackError: String?,
        status: ProjectSearchStatus
    ) {
        let previousSelectedResultID = selectedResultID ?? selectedResult?.id

        results = newResults
        self.totalMatched = totalMatched
        self.nextFileOffset = nextFileOffset
        self.regexFallbackError = regexFallbackError
        self.status = status
        self.lastErrorMessage = nil
        self.isSearching = false
        self.isLoadingMore = false

        if let previousSelectedResultID,
           let newIndex = newResults.firstIndex(where: { $0.id == previousSelectedResultID }) {
            setSelection(index: newIndex, updatePreview: false)
        } else if newResults.isEmpty {
            setSelection(index: nil, updatePreview: false)
        } else {
            setSelection(index: 0, updatePreview: false)
        }

        updatePreviewForSelection()
    }

    private func appendSearchResults(
        _ newResults: [ProjectSearchResult],
        totalMatched: Int,
        nextFileOffset: Int?,
        regexFallbackError: String?,
        status: ProjectSearchStatus,
        selectedResultID: String?
    ) {
        results = mergeUniqueResults(existing: results, additional: newResults)
        self.totalMatched = totalMatched
        self.nextFileOffset = nextFileOffset
        self.regexFallbackError = regexFallbackError
        self.status = status
        self.isLoadingMore = false
        self.lastErrorMessage = nil

        if let selectedResultID,
           let newIndex = results.firstIndex(where: { $0.id == selectedResultID }) {
            setSelection(index: newIndex, updatePreview: false)
        } else if results.isEmpty {
            setSelection(index: nil, updatePreview: false)
        } else if !results.indices.contains(selectedIndex) {
            setSelection(index: 0, updatePreview: false)
        } else {
            setSelection(index: selectedIndex, updatePreview: false)
        }

        updatePreviewForSelection()
    }

    private func mergeUniqueResults(
        existing: [ProjectSearchResult],
        additional: [ProjectSearchResult]
    ) -> [ProjectSearchResult] {
        var seenIDs = Set(existing.map(\.id))
        var merged = existing

        for result in additional where !seenIDs.contains(result.id) {
            merged.append(result)
            seenIDs.insert(result.id)
        }

        return merged
    }

    private func setSelection(index: Int?, updatePreview: Bool = true) {
        if let index, results.indices.contains(index) {
            selectedIndex = index
            selectedResultID = results[index].id
        } else {
            selectedIndex = 0
            selectedResultID = nil
        }

        if updatePreview {
            updatePreviewForSelection()
        }
    }

    private func isCurrentSearch(
        revision: Int,
        query: String,
        mode: ProjectSearchMode,
        grepMode: ProjectSearchGrepMode
    ) -> Bool {
        revision == searchRevision &&
        query == searchQueryTrimmed &&
        mode == self.mode &&
        grepMode == self.grepMode
    }

    private func isCurrentContentLoad(query: String, grepMode: ProjectSearchGrepMode) -> Bool {
        mode == .content &&
        query == searchQueryTrimmed &&
        grepMode == self.grepMode
    }

    private func refreshStatus() {
        statusTask?.cancel()
        statusTask = Task { [weak self] in
            guard let self else { return }
            do {
                let status = try await self.searchService.scanProgress(worktreePath: self.worktreePath)
                guard !Task.isCancelled else { return }
                self.status = status
            } catch {
                guard !Task.isCancelled else { return }
            }
        }
    }

    private func updatePreviewForSelection() {
        previewTask?.cancel()

        guard let selectedResult else {
            previewState = .idle(Self.previewPlaceholder(for: mode, query: searchQueryTrimmed))
            return
        }

        previewState = .loading
        previewTask = Task { [weak self] in
            guard let self else { return }

            do {
                try await Task.sleep(for: .milliseconds(80))
            } catch {
                return
            }

            guard !Task.isCancelled else { return }

            let preview = await self.searchService.loadPreview(for: selectedResult)
            guard !Task.isCancelled else { return }
            self.previewState = preview
        }
    }

    private func persistGrepMode(_ grepMode: ProjectSearchGrepMode) {
        UserDefaults.standard.set(grepMode.rawValue, forKey: Self.grepModeStorageKey(for: worktreePath))
    }

    private static func loadPersistedGrepMode(for worktreePath: String) -> ProjectSearchGrepMode {
        let rawValue = UserDefaults.standard.string(forKey: grepModeStorageKey(for: worktreePath))
        return rawValue.flatMap(ProjectSearchGrepMode.init(rawValue:)) ?? .plain
    }

    private static func grepModeStorageKey(for worktreePath: String) -> String {
        let digest = SHA256.hash(data: Data(worktreePath.utf8))
        let suffix = digest.map { String(format: "%02x", $0) }.joined()
        return "projectSearch.grepMode.\(suffix)"
    }

    private static func previewPlaceholder(for mode: ProjectSearchMode, query: String) -> String {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        if mode == .content && trimmedQuery.isEmpty {
            return "Type to search file contents."
        }

        if trimmedQuery.isEmpty && mode == .files {
            return "Select a file to preview."
        }

        return "Select a result to preview."
    }
}
