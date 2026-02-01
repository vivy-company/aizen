//
//  UnifiedAutocompleteHandler.swift
//  aizen
//
//  Unified handler for @ file mentions and / commands autocomplete
//

import ACP
import Combine
import os.log
import SwiftUI

@MainActor
class UnifiedAutocompleteHandler: ObservableObject {
    @Published var state = AutocompleteState()

    private let logger = Logger.forCategory("Autocomplete")
    private let fileSearchService = FileSearchService.shared
    private var fileIndex: [FileSearchIndexResult] = []
    private var searchTask: Task<Void, Never>?
    private var isIndexing = false

    // Dependencies
    weak var agentSession: AgentSession?
    var worktreePath: String = ""
    private var lastSearchedText: String = ""
    private var isNavigating = false  // Prevents search from resetting selection during navigation

    // MARK: - Index Management

    func indexWorktree(forceRefresh: Bool = false) async {
        guard !worktreePath.isEmpty, !isIndexing else { return }
        isIndexing = true
        defer { isIndexing = false }

        do {
            // Clear cache to pick up gitignore changes
            if forceRefresh || fileIndex.isEmpty {
                await fileSearchService.clearCache(for: worktreePath)
            }
            fileIndex = try await fileSearchService.indexDirectory(worktreePath)
            logger.debug("Indexed \(self.fileIndex.count) files in worktree")
        } catch {
            logger.error("Failed to index worktree: \(error.localizedDescription)")
            fileIndex = []
        }
    }

    // MARK: - Trigger Detection

    func detectTrigger(in text: String, cursorPosition: Int) -> (trigger: AutocompleteTrigger, range: NSRange)? {
        guard cursorPosition > 0, cursorPosition <= text.count else { return nil }

        let textBeforeCursor = String(text.prefix(cursorPosition))

        var lastTriggerIndex: String.Index?
        var triggerChar: Character?

        // Scan backwards from cursor to find trigger
        for char in textBeforeCursor.reversed() {
            if char.isWhitespace || char.isNewline {
                break
            }

            if char == "@" || char == "/" {
                // Find actual position of trigger
                var tempIndex = textBeforeCursor.endIndex
                for (i, c) in textBeforeCursor.enumerated().reversed() {
                    if c == char {
                        tempIndex = textBeforeCursor.index(textBeforeCursor.startIndex, offsetBy: i)
                        break
                    }
                    if c.isWhitespace || c.isNewline {
                        break
                    }
                }

                if tempIndex != textBeforeCursor.endIndex {
                    lastTriggerIndex = tempIndex
                    triggerChar = char
                }
                break
            }
        }

        guard let triggerIndex = lastTriggerIndex,
              let char = triggerChar else { return nil }

        let triggerOffset = text.distance(from: text.startIndex, to: triggerIndex)

        // Validate: trigger must be at word boundary
        if triggerOffset > 0 {
            let prevIndex = text.index(text.startIndex, offsetBy: triggerOffset - 1)
            let prevChar = text[prevIndex]
            if !prevChar.isWhitespace && !prevChar.isNewline {
                return nil
            }
        }

        // Extract query
        let queryStartOffset = triggerOffset + 1
        let query: String
        if queryStartOffset < cursorPosition {
            let queryStart = text.index(text.startIndex, offsetBy: queryStartOffset)
            let queryEnd = text.index(text.startIndex, offsetBy: cursorPosition)
            query = String(text[queryStart..<queryEnd])
        } else {
            query = ""
        }

        let range = NSRange(location: triggerOffset, length: cursorPosition - triggerOffset)

        switch char {
        case "@":
            return (.file(query: query), range)
        case "/":
            // Commands only trigger at start or after newline
            let isAtStart = triggerOffset == 0
            let isAfterNewline = triggerOffset > 0 && text[text.index(text.startIndex, offsetBy: triggerOffset - 1)].isNewline
            if isAtStart || isAfterNewline {
                return (.command(query: query), range)
            }
            return nil
        default:
            return nil
        }
    }

    // MARK: - Text Change Handling

    func handleTextChange(text: String, cursorPosition: Int, cursorRect: NSRect) {
        guard let (trigger, range) = detectTrigger(in: text, cursorPosition: cursorPosition) else {
            dismissAutocomplete()
            lastSearchedText = ""
            return
        }

        state.trigger = trigger
        state.triggerRange = range
        state.cursorRect = cursorRect
        state.isActive = true

        // Only search if text actually changed (avoid re-searching on cursor-only changes)
        let textToSearch = text
        if textToSearch == lastSearchedText && !state.items.isEmpty {
            // Text hasn't changed, just update cursor position
            return
        }
        lastSearchedText = textToSearch

        // Debounced search
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms debounce
            guard !Task.isCancelled else { return }
            await performSearch(for: trigger)
        }
    }

    private func performSearch(for trigger: AutocompleteTrigger) async {
        // Compute new items based on trigger
        let newItems: [AutocompleteItem]

        switch trigger {
        case .file(let query):
            // Index on-demand if fileIndex is empty
            if fileIndex.isEmpty && !worktreePath.isEmpty {
                await indexWorktree(forceRefresh: true)
            }
            let results = await fileSearchService.search(query: query, in: fileIndex, worktreePath: worktreePath, limit: 20)
            newItems = results.prefix(10).map { .file($0) }

        case .command(let query):
            let clientSideCommands = ClientCommandHandler.shared.availableCommands
            let agentCommands = agentSession?.availableCommands ?? []
            let allCommands = clientSideCommands + agentCommands
            
            let filtered: [AvailableCommand]
            if query.isEmpty {
                filtered = Array(allCommands.prefix(10))
            } else {
                filtered = allCommands.filter {
                    $0.name.lowercased().hasPrefix(query.lowercased()) ||
                    $0.description.lowercased().contains(query.lowercased())
                }
            }
            newItems = filtered.prefix(10).map { .command($0) }
        }

        // If user is actively navigating, don't update items or selection
        // This prevents search from interfering with keyboard navigation
        guard !isNavigating else {
            logger.debug("Skipping search update - user is navigating")
            return
        }

        // Capture current selection for preservation attempt
        let currentSelectedItem = state.selectedItem
        let currentSelectedIndex = state.selectedIndex

        // Update items
        state.items = newItems

        // Try to preserve selection if the currently selected item is still in new results
        if let currentItem = currentSelectedItem,
           let newIndex = newItems.firstIndex(where: { $0.id == currentItem.id }) {
            state.selectedIndex = newIndex
        } else if !newItems.isEmpty {
            // Clamp selection to valid range instead of always resetting to 0
            // This preserves approximate position when items change
            state.selectedIndex = min(currentSelectedIndex, newItems.count - 1)
        } else {
            state.selectedIndex = 0
        }
    }

    // MARK: - Navigation

    func navigateUp() -> Bool {
        guard state.isActive, !state.items.isEmpty else { return false }
        // Cancel pending search to prevent it from resetting selection
        searchTask?.cancel()
        isNavigating = true
        let oldIndex = state.selectedIndex
        // Force SwiftUI to recognize the change
        objectWillChange.send()
        state.selectPrevious()
        logger.debug("navigateUp: \(oldIndex) -> \(self.state.selectedIndex) (items=\(self.state.items.count))")
        // Reset navigation flag after a short delay
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            self.isNavigating = false
        }
        return true
    }

    func navigateDown() -> Bool {
        guard state.isActive, !state.items.isEmpty else { return false }
        // Cancel pending search to prevent it from resetting selection
        searchTask?.cancel()
        isNavigating = true
        let oldIndex = state.selectedIndex
        // Force SwiftUI to recognize the change
        objectWillChange.send()
        state.selectNext()
        logger.debug("navigateDown: \(oldIndex) -> \(self.state.selectedIndex) (items=\(self.state.items.count))")
        // Reset navigation flag after a short delay
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            self.isNavigating = false
        }
        return true
    }

    func selectCurrent() -> (replacement: String, range: NSRange)? {
        guard state.isActive else {
            logger.debug("selectCurrent: autocomplete not active")
            return nil
        }
        guard let item = state.selectedItem else {
            logger.debug("selectCurrent: no selected item (index=\(self.state.selectedIndex), items=\(self.state.items.count))")
            return nil
        }
        guard let range = state.triggerRange else {
            logger.debug("selectCurrent: no trigger range")
            return nil
        }

        let replacement: String
        switch item {
        case .file(let result):
            replacement = "@\(result.relativePath) "
        case .command(let command):
            replacement = "/\(command.name) "
        }

        logger.debug("selectCurrent: selecting '\(replacement)' at range \(range.location)-\(range.location + range.length)")
        dismissAutocomplete()
        return (replacement, range)
    }

    func dismissAutocomplete() {
        searchTask?.cancel()
        // Defer state reset to avoid "Publishing changes from within view updates" warning
        Task { @MainActor in
            self.state.reset()
        }
        lastSearchedText = ""
    }

    func selectItem(_ item: AutocompleteItem) {
        guard state.isActive,
              let index = state.items.firstIndex(where: { $0.id == item.id }) else {
            return
        }
        state.selectedIndex = index
    }

    // MARK: - Direct Update

    func updateCursorRect(_ rect: NSRect) {
        state.cursorRect = rect
    }
}
