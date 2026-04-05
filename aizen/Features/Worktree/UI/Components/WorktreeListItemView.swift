//
//  WorktreeListItemView.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import SwiftUI
import os.log

struct WorktreeListItemView: View {
    @ObservedObject var worktree: Worktree
    let isSelected: Bool
    @ObservedObject var repositoryManager: WorkspaceRepositoryStore
    let allWorktrees: [Worktree]
    @Binding var selectedWorktree: Worktree?
    @ObservedObject var tabStateManager: WorktreeTabStateStore
    @Environment(\.controlActiveState) var controlActiveState

    let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen.app", category: "WorktreeListItemView")

    @AppStorage("defaultTerminalBundleId") var defaultTerminalBundleId: String?
    @AppStorage("defaultEditorBundleId") var defaultEditorBundleId: String?

    @State var showingDetails = false
    @State var showingDeleteConfirmation = false
    @State var hasUnsavedChanges = false
    @State var errorMessage: String?
    @State var worktreeStatuses: [WorktreeStatusInfo] = []
    @State var isLoadingStatuses = false
    @State var mergeErrorMessage: String?
    @State var mergeConflictFiles: [String] = []
    @State var showingMergeConflict = false
    @State var showingMergeSuccess = false
    @State var mergeSuccessMessage = ""
    @State var availableBranches: [BranchInfo] = []
    @State var isLoadingBranches = false
    @State var showingBranchSelector = false
    @State var branchSwitchError: String?
    @State var showingNoteEditor = false

    var body: some View {
        rowContent
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isSelected
                ? RoundedRectangle(cornerRadius: 6)
                    .fill(selectionFillColor)
                : nil
        )
        .contentShape(Rectangle())
        .contextMenu {
            contextMenuContent
        }
        .worktreeListItemPresentation(view: self)
    }

}
