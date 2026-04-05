import SwiftUI

extension DetailsTabView {
    func detailsTabLifecycle() -> some ViewModifier {
        DetailsTabLifecycleModifier(view: self)
    }
}

private struct DetailsTabLifecycleModifier: ViewModifier {
    @Binding var showingDeleteConfirmation: Bool
    @Binding var hasUnsavedChanges: Bool

    let worktree: Worktree
    let refreshStatus: () -> Void
    let deleteWorktree: () -> Void

    init(view: DetailsTabView) {
        _showingDeleteConfirmation = view.$showingDeleteConfirmation
        _hasUnsavedChanges = view.$hasUnsavedChanges
        worktree = view.worktree
        refreshStatus = view.refreshStatus
        deleteWorktree = view.deleteWorktree
    }

    func body(content: Content) -> some View {
        content
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
                    Text("worktree.detail.deleteConfirmMessage", bundle: .main)
                }
            }
    }
}
