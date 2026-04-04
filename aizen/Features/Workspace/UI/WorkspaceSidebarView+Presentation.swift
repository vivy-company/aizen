import SwiftUI

private struct WorkspaceSidebarPresentationModifier: ViewModifier {
    @Binding var showingWorkspaceSheet: Bool
    @Binding var showingWorkspaceSwitcher: Bool
    @Binding var workspaceToEdit: Workspace?
    @Binding var showingSupportSheet: Bool
    @Binding var missingRepository: WorkspaceRepositoryStore.MissingRepository?
    @Binding var selectedWorkspace: Workspace?
    @Binding var selectedRepository: Repository?
    @Binding var selectedWorktree: Worktree?

    let workspaces: [Workspace]
    let repositoryManager: WorkspaceRepositoryStore

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showingWorkspaceSheet) {
                WorkspaceCreateSheet(repositoryManager: repositoryManager)
            }
            .sheet(isPresented: $showingWorkspaceSwitcher) {
                WorkspaceSwitcherSheet(
                    repositoryManager: repositoryManager,
                    workspaces: workspaces,
                    selectedWorkspace: $selectedWorkspace
                )
            }
            .sheet(item: $workspaceToEdit) { workspace in
                WorkspaceEditSheet(workspace: workspace, repositoryManager: repositoryManager)
            }
            .sheet(isPresented: $showingSupportSheet) {
                SupportSheet()
            }
            .sheet(item: $missingRepository) { missing in
                MissingRepositorySheet(
                    missing: missing,
                    repositoryManager: repositoryManager,
                    selectedRepository: $selectedRepository,
                    selectedWorktree: $selectedWorktree,
                    onDismiss: { missingRepository = nil }
                )
            }
    }
}

extension View {
    func workspaceSidebarPresentation(view: WorkspaceSidebarView) -> some View {
        modifier(
            WorkspaceSidebarPresentationModifier(
                showingWorkspaceSheet: view.$showingWorkspaceSheet,
                showingWorkspaceSwitcher: view.$showingWorkspaceSwitcher,
                workspaceToEdit: view.$workspaceToEdit,
                showingSupportSheet: view.$showingSupportSheet,
                missingRepository: view.$missingRepository,
                selectedWorkspace: view.$selectedWorkspace,
                selectedRepository: view.$selectedRepository,
                selectedWorktree: view.$selectedWorktree,
                workspaces: view.workspaces,
                repositoryManager: view.repositoryManager
            )
        )
    }
}
