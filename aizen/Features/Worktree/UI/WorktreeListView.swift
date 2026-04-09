//
//  WorktreeListView.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import SwiftUI

struct WorktreeListView: View {
    @ObservedObject var repository: Repository
    @Binding var selectedWorktree: Worktree?
    @ObservedObject var repositoryManager: WorkspaceRepositoryStore
    @ObservedObject var tabStateManager: WorktreeTabStateStore
    @ObservedObject var workspaceGraphQueryController: WorkspaceGraphQueryController
    @Environment(\.colorScheme) var colorScheme

    @State var showingCreateWorktree = false
    @State var searchText = ""
    @AppStorage("worktreeStatusFilters") var storedStatusFilters: String = ""
    @AppStorage("zenModeEnabled") var zenModeEnabled = false
}

#Preview {
    WorktreeListView(
        repository: Repository(),
        selectedWorktree: .constant(nil),
        repositoryManager: WorkspaceRepositoryStore(viewContext: PersistenceController.preview.container.viewContext),
        tabStateManager: WorktreeTabStateStore(),
        workspaceGraphQueryController: WorkspaceGraphQueryController(
            viewContext: PersistenceController.preview.container.viewContext
        )
    )
}
