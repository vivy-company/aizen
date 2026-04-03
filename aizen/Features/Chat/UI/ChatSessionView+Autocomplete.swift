import ACP
import AppKit
import CoreData
import SwiftUI
import VVChatTimeline

extension ChatSessionView {
    func handleAutocompleteSelection() {
        guard let (replacement, range) = viewModel.autocompleteHandler.selectCurrent() else { return }
        let nsString = inputText as NSString
        inputText = nsString.replacingCharacters(in: range, with: replacement)
        pendingCursorPosition = range.location + replacement.count
    }

    func setupAutocompleteWindow() {
        let window = AutocompleteWindowController()
        window.configureActions(
            onTap: { item in
                // Defer to avoid "Publishing changes from within view updates" warning
                Task { @MainActor in
                    viewModel.autocompleteHandler.selectItem(item)
                    handleAutocompleteSelection()
                }
            },
            onSelect: {
                handleAutocompleteSelection()
            }
        )
        autocompleteWindow = window
    }

    func updateAutocompleteWindow(state: AutocompleteState) {
        guard let window = autocompleteWindow else { return }

        let parentWindow = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible })

        if state.isActive, let parentWindow = parentWindow {
            window.update(state: state)
            window.show(at: state.cursorRect, attachedTo: parentWindow)
        } else {
            window.dismiss()
        }
    }
}
