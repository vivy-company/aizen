//
//  WorktreeDetailsTab.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 04.11.25.
//

import SwiftUI
import os.log

struct DetailsTabView: View {
    @ObservedObject var worktree: Worktree
    @ObservedObject var repositoryManager: WorkspaceRepositoryStore
    var onWorktreeDeleted: ((Worktree?) -> Void)?

    let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen", category: "DetailsTabView")
    @State var currentBranch = ""
    @State var ahead = 0
    @State var behind = 0
    @State var isLoading = false
    @State var showingDeleteConfirmation = false
    @State var hasUnsavedChanges = false
    @State var errorMessage: String?

    var body: some View {
        detailsContent
            .modifier(detailsTabLifecycle())
    }
}
