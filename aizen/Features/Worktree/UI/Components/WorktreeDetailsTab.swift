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
        .navigationTitle(String(localized: "worktree.list.title"))
        .toolbar {
            Button {
                refreshStatus()
            } label: {
                Label(String(localized: "worktree.detail.refresh"), systemImage: "arrow.clockwise")
            }
        }
        .task {
            refreshStatus()
        }
        .alert(hasUnsavedChanges ? String(localized: "worktree.detail.unsavedChangesTitle") : String(localized: "worktree.detail.deleteConfirmTitle"), isPresented: $showingDeleteConfirmation) {
            Button(String(localized: "worktree.create.cancel"), role: .cancel) {}
            Button(String(localized: "worktree.detail.delete"), role: .destructive) {
                deleteWorktree()
            }
        } message: {
            if hasUnsavedChanges {
                Text(String(localized: "worktree.detail.unsavedChangesMessage \(worktree.branch ?? String(localized: "worktree.list.unknown"))"))
            } else {
                Text("worktree.detail.deleteConfirmMessage", bundle: .main)
            }
        }
    }
}
