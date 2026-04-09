//
//  CommandPaletteWindowController+Lifecycle.swift
//  aizen
//
//  Lifecycle and keyboard shortcut wiring for the command palette
//

import SwiftUI

extension CommandPaletteContent {
    struct SnapshotSyncKey: Hashable {
        let worktreeCount: Int
        let workspaceCount: Int
        let currentWorktreeId: String?
    }

    var snapshotSyncKey: SnapshotSyncKey {
        SnapshotSyncKey(
            worktreeCount: workspaceGraphQueryController.worktrees.count,
            workspaceCount: workspaceGraphQueryController.workspaces.count,
            currentWorktreeId: currentWorktreeId
        )
    }

    func syncSnapshots() {
        viewModel.updateSnapshot(workspaceGraphQueryController.worktrees, currentWorktreeId: currentWorktreeId)
        viewModel.updateWorkspaceSnapshot(workspaceGraphQueryController.workspaces)
    }

}

struct CommandPaletteLifecycleModifier: ViewModifier {
    let content: CommandPaletteContent

    func body(content view: Content) -> some View {
        view
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    self.content.isSearchFocused = true
                }
            }
            .task(id: self.content.snapshotSyncKey) {
                self.content.syncSnapshots()
            }
    }
}

struct CommandPaletteKeyboardShortcutModifier: ViewModifier {
    let content: CommandPaletteContent

    func body(content view: Content) -> some View {
        view.background {
            Group {
                Button("") {
                    self.content.interaction.didUseKeyboard()
                    self.content.viewModel.moveSelectionDown()
                }
                .keyboardShortcut(.downArrow, modifiers: [])

                Button("") {
                    self.content.interaction.didUseKeyboard()
                    self.content.viewModel.moveSelectionUp()
                }
                .keyboardShortcut(.upArrow, modifiers: [])

                Button("") {
                    self.content.interaction.didUseKeyboard()
                    if let action = self.content.viewModel.selectedNavigationAction() {
                        self.content.handleSelection(action)
                    }
                }
                .keyboardShortcut(.return, modifiers: [])

                Button("") { self.content.onClose() }
                    .keyboardShortcut(.escape, modifiers: [])

                Button("") {
                    self.content.interaction.didUseKeyboard()
                    self.content.viewModel.setScope(.all)
                }
                .keyboardShortcut("1", modifiers: .command)

                Button("") {
                    self.content.interaction.didUseKeyboard()
                    self.content.viewModel.setScope(.currentProject)
                }
                .keyboardShortcut("2", modifiers: .command)

                Button("") {
                    self.content.interaction.didUseKeyboard()
                    self.content.viewModel.setScope(.workspace)
                }
                .keyboardShortcut("3", modifiers: .command)

                Button("") {
                    self.content.interaction.didUseKeyboard()
                    self.content.viewModel.setScope(.tabs)
                }
                .keyboardShortcut("4", modifiers: .command)
            }
            .hidden()
        }
    }
}
