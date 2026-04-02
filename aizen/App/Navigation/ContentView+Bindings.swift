//
//  ContentView+Bindings.swift
//  aizen
//
//  Created by Codex on 2026-04-03.
//

import SwiftUI

extension ContentView {
    var selectedWorkspaceBinding: Binding<Workspace?> {
        Binding(
            get: { selectionStore.selectedWorkspace },
            set: { selectWorkspace($0) }
        )
    }

    var crossProjectSelectionBinding: Binding<Bool> {
        Binding(
            get: { selectionStore.isCrossProjectSelected },
            set: { setCrossProjectSelected($0) }
        )
    }

    var selectedRepositoryBinding: Binding<Repository?> {
        Binding(
            get: { selectionStore.selectedRepository },
            set: { selectRepository($0) }
        )
    }

    var selectedWorktreeBinding: Binding<Worktree?> {
        Binding(
            get: { selectionStore.selectedWorktree },
            set: { selectWorktree($0) }
        )
    }
}
