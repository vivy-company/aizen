//
//  UnifiedAutocompleteHandler+Runtime.swift
//  aizen
//
//  Unified handler runtime helpers for trigger detection, search, and navigation.
//

import ACP
import Combine
import os.log
import SwiftUI

@MainActor
extension UnifiedAutocompleteHandler {
    // MARK: - Index Management

    func indexWorktree(forceRefresh: Bool = false) async {
        guard !worktreePath.isEmpty, !isIndexing else { return }
        isIndexing = true
        defer { isIndexing = false }

        do {
            if forceRefresh || fileIndex.isEmpty {
                await fileSearchService.clearCache(for: worktreePath)
            }
            fileIndex = try await fileSearchService.indexDirectory(worktreePath)
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

        for char in textBeforeCursor.reversed() {
            if char.isWhitespace || char.isNewline {
                break
            }

            if char == "@" || char == "/" {
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
        if triggerOffset > 0 {
            let prevIndex = text.index(text.startIndex, offsetBy: triggerOffset - 1)
            let prevChar = text[prevIndex]
            if !prevChar.isWhitespace && !prevChar.isNewline {
                return nil
            }
        }

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

        let textToSearch = text
        if textToSearch == lastSearchedText && !state.items.isEmpty {
            return
        }
        lastSearchedText = textToSearch

        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard !Task.isCancelled else { return }
            await performSearch(for: trigger)
        }
    }

    private func performSearch(for trigger: AutocompleteTrigger) async {
        let newItems: [AutocompleteItem]

        switch trigger {
        case .file(let query):
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

        guard !isNavigating else {
            logger.debug("Skipping search update - user is navigating")
            return
        }

        let currentSelectedItem = state.selectedItem
        let currentSelectedIndex = state.selectedIndex

        state.items = newItems

        if let currentItem = currentSelectedItem,
           let newIndex = newItems.firstIndex(where: { $0.id == currentItem.id }) {
            state.selectedIndex = newIndex
        } else if !newItems.isEmpty {
            state.selectedIndex = min(currentSelectedIndex, newItems.count - 1)
        } else {
            state.selectedIndex = 0
        }
    }

    // MARK: - Navigation

    func navigateUp() -> Bool {
        guard state.isActive, !state.items.isEmpty else { return false }
        searchTask?.cancel()
        isNavigating = true
        let oldIndex = state.selectedIndex
        objectWillChange.send()
        state.selectPrevious()
        logger.debug("navigateUp: \(oldIndex) -> \(self.state.selectedIndex) (items=\(self.state.items.count))")
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            self.isNavigating = false
        }
        return true
    }

    func navigateDown() -> Bool {
        guard state.isActive, !state.items.isEmpty else { return false }
        searchTask?.cancel()
        isNavigating = true
        let oldIndex = state.selectedIndex
        objectWillChange.send()
        state.selectNext()
        logger.debug("navigateDown: \(oldIndex) -> \(self.state.selectedIndex) (items=\(self.state.items.count))")
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            self.isNavigating = false
        }
        return true
    }
}
