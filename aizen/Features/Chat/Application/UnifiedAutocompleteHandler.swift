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

    let logger = Logger.forCategory("Autocomplete")
    let fileSearchService = FileSearchService.shared
    var fileIndex: [FileSearchIndexResult] = []
    var searchTask: Task<Void, Never>?
    var isIndexing = false

    // Dependencies
    weak var agentSession: ChatAgentSession?
    var worktreePath: String = ""
    var lastSearchedText: String = ""
    var isNavigating = false  // Prevents search from resetting selection during navigation

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
