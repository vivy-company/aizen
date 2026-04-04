import SwiftUI

private struct WorktreeListItemPresentationModifier: ViewModifier {
    @Binding var showingDetails: Bool
    @Binding var showingBranchSelector: Bool
    @Binding var showingNoteEditor: Bool
    @Binding var showingDeleteConfirmation: Bool
    @Binding var hasUnsavedChanges: Bool
    @Binding var errorMessage: String?
    @Binding var showingMergeConflict: Bool
    @Binding var mergeConflictFiles: [String]
    @Binding var showingMergeSuccess: Bool
    @Binding var mergeSuccessMessage: String
    @Binding var mergeErrorMessage: String?
    @Binding var branchSwitchError: String?

    let worktree: Worktree
    let repositoryManager: WorkspaceRepositoryStore
    let switchToBranch: (BranchInfo) -> Void
    let createNewBranch: (String) -> Void
    let deleteWorktree: () -> Void
    let loadWorktreeStatuses: () -> Void

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showingDetails) {
                WorktreeDetailsSheet(worktree: worktree, repositoryManager: repositoryManager)
            }
            .sheet(isPresented: $showingBranchSelector) {
                if let repo = worktree.repository {
                    BranchSelectorView(
                        repository: repo,
                        repositoryManager: repositoryManager,
                        selectedBranch: .constant(nil),
                        onSelectBranch: switchToBranch,
                        allowCreation: true,
                        onCreateBranch: { branchName in
                            createNewBranch(branchName)
                        }
                    )
                }
            }
            .sheet(isPresented: $showingNoteEditor) {
                NoteEditorView(
                    note: Binding(
                        get: { worktree.note ?? "" },
                        set: { worktree.note = $0 }
                    ),
                    title: String(localized: "worktree.note.title \(worktree.branch ?? "")"),
                    onSave: {
                        try? repositoryManager.updateWorktreeNote(worktree, note: worktree.note)
                    }
                )
            }
            .alert(
                hasUnsavedChanges
                    ? String(localized: "worktree.detail.unsavedChangesTitle")
                    : String(localized: "worktree.detail.deleteConfirmTitle"),
                isPresented: $showingDeleteConfirmation
            ) {
                Button(String(localized: "worktree.create.cancel"), role: .cancel) {}
                Button(String(localized: "worktree.detail.delete"), role: .destructive) {
                    deleteWorktree()
                }
            } message: {
                if hasUnsavedChanges {
                    Text(
                        String(
                            localized:
                                "worktree.detail.unsavedChangesMessage \(worktree.branch ?? String(localized: "worktree.list.unknown"))"
                        )
                    )
                } else {
                    Text(
                        String(
                            localized:
                                "worktree.detail.deleteConfirmMessageWithName \(worktree.branch ?? String(localized: "worktree.list.unknown"))"
                        )
                    )
                }
            }
            .alert(String(localized: "worktree.list.error"), isPresented: .constant(errorMessage != nil)) {
                Button(String(localized: "worktree.list.ok")) {
                    errorMessage = nil
                }
            } message: {
                if let errorMessage {
                    Text(errorMessage)
                }
            }
            .alert(String(localized: "worktree.merge.conflict"), isPresented: $showingMergeConflict) {
                Button(String(localized: "worktree.list.ok")) {
                    mergeConflictFiles = []
                }
            } message: {
                VStack(alignment: .leading) {
                    Text(String(localized: "worktree.merge.conflictMessage"))
                    ForEach(mergeConflictFiles, id: \.self) { file in
                        Text("• \(file)")
                    }
                    Text(String(localized: "worktree.merge.resolveHint"))
                }
            }
            .alert(String(localized: "worktree.merge.successful"), isPresented: $showingMergeSuccess) {
                Button(String(localized: "worktree.list.ok")) {}
            } message: {
                Text(mergeSuccessMessage)
            }
            .alert(String(localized: "worktree.merge.error"), isPresented: .constant(mergeErrorMessage != nil)) {
                Button(String(localized: "worktree.list.ok")) {
                    mergeErrorMessage = nil
                }
            } message: {
                if let mergeErrorMessage {
                    Text(mergeErrorMessage)
                }
            }
            .alert(String(localized: "worktree.branch.switchError"), isPresented: .constant(branchSwitchError != nil)) {
                Button(String(localized: "worktree.list.ok")) {
                    branchSwitchError = nil
                }
            } message: {
                if let branchSwitchError {
                    Text(branchSwitchError)
                }
            }
            .onAppear {
                loadWorktreeStatuses()
            }
    }
}

extension View {
    func worktreeListItemPresentation(view: WorktreeListItemView) -> some View {
        modifier(
            WorktreeListItemPresentationModifier(
                showingDetails: view.$showingDetails,
                showingBranchSelector: view.$showingBranchSelector,
                showingNoteEditor: view.$showingNoteEditor,
                showingDeleteConfirmation: view.$showingDeleteConfirmation,
                hasUnsavedChanges: view.$hasUnsavedChanges,
                errorMessage: view.$errorMessage,
                showingMergeConflict: view.$showingMergeConflict,
                mergeConflictFiles: view.$mergeConflictFiles,
                showingMergeSuccess: view.$showingMergeSuccess,
                mergeSuccessMessage: view.$mergeSuccessMessage,
                mergeErrorMessage: view.$mergeErrorMessage,
                branchSwitchError: view.$branchSwitchError,
                worktree: view.worktree,
                repositoryManager: view.repositoryManager,
                switchToBranch: view.switchToBranch,
                createNewBranch: view.createNewBranch,
                deleteWorktree: view.deleteWorktree,
                loadWorktreeStatuses: view.loadWorktreeStatuses
            )
        )
    }
}
