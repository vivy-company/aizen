import SwiftUI

struct WorktreeListItemPresentationModifier: ViewModifier {
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
        applyAlerts(
            to: content
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
        )
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
