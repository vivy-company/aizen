import SwiftUI

extension WorktreeListItemPresentationModifier {
    func applyAlerts<V: View>(to content: V) -> some View {
        content
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
    }
}
