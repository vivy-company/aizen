//
//  ContentView.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import ACP
import CoreData
import SwiftUI

struct ContentView: View {
    @Environment(\.managedObjectContext) var viewContext
    @ObservedObject var repositoryManager: RepositoryManager
    @StateObject var selectionStore = AppNavigationSelectionStore()
    @StateObject var tabStateManager = WorktreeTabStateStore()
    @StateObject var navigator = AppWorktreeNavigator()

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Workspace.order, ascending: true)],
        animation: .default)
    var workspaces: FetchedResults<Workspace>

    @State var searchText = ""
    @State var showingAddRepository = false
    @State var columnVisibility: NavigationSplitViewVisibility = .all
    @AppStorage("hasShownOnboarding") var hasShownOnboarding = false
    @AppStorage("hasShownCrossProjectOnboarding") var hasShownCrossProjectOnboarding = false
    @State var showingOnboarding = false
    @State var showingCrossProjectOnboarding = false
    @AppStorage("zenModeEnabled") var zenModeEnabled = false

    @State var saveTask: Task<Void, Never>?

    // Git changes overlay state (passed from RootView)
    @Binding var gitChangesContext: GitChangesContext?

    // Persistent selection storage
    @AppStorage("selectedWorkspaceId") var selectedWorkspaceId: String?
    @AppStorage("selectedRepositoryId") var selectedRepositoryId: String?
    @AppStorage("selectedWorktreeId") var selectedWorktreeId: String?
    @AppStorage("selectedWorktreeByRepository") var selectedWorktreeByRepositoryData: String = "{}"
    @AppStorage("worktreeMRUOrder") var worktreeMRUOrderData: String = "[]"
    let crossProjectRepositoryMarker = "__aizen.cross_project.workspace_repo__"

    init(context: NSManagedObjectContext, repositoryManager: RepositoryManager, gitChangesContext: Binding<GitChangesContext?>) {
        self.repositoryManager = repositoryManager
        _gitChangesContext = gitChangesContext
    }

    var body: some View {
        withLifecycleHandlers(
            withPresentationSheets(
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    // Left sidebar - workspaces and repositories
                    WorkspaceSidebarView(
                        workspaces: Array(workspaces),
                        selectedWorkspace: selectedWorkspaceBinding,
                        isCrossProjectSelected: crossProjectSelectionBinding,
                        selectedRepository: selectedRepositoryBinding,
                        selectedWorktree: selectedWorktreeBinding,
                        searchText: $searchText,
                        showingAddRepository: $showingAddRepository,
                        repositoryManager: repositoryManager
                    )
                    .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 300)
                } content: {
                    AppNavigationContentColumn(
                        isCrossProjectSelected: selectionStore.isCrossProjectSelected,
                        repository: selectionStore.selectedRepository,
                        selectedWorktree: selectedWorktreeBinding,
                        repositoryManager: repositoryManager,
                        tabStateManager: tabStateManager,
                        zenModeEnabled: zenModeEnabled
                    )
                } detail: {
                    AppNavigationDetailColumn(
                        isCrossProjectSelected: selectionStore.isCrossProjectSelected,
                        crossProjectWorktree: selectionStore.crossProjectWorktree,
                        selectedWorktree: selectionStore.selectedWorktree,
                        repositoryManager: repositoryManager,
                        tabStateManager: tabStateManager,
                        gitChangesContext: $gitChangesContext,
                        onSelectCrossProjectWorktree: selectCrossProjectWorktree,
                        onPrepareCrossProjectWorkspaceIfNeeded: prepareCrossProjectWorkspaceIfNeeded,
                        onSelectWorktree: selectWorktree
                    )
                }
            )
        )
    }

}



@ViewBuilder
func placeholderView(
    titleKey: LocalizedStringKey,
    systemImage: String,
    descriptionKey: LocalizedStringKey
) -> some View {
    if #available(macOS 14.0, *) {
        ContentUnavailableView(
            titleKey,
            systemImage: systemImage,
            description: Text(descriptionKey)
        )
    } else {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 50))
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                Text(titleKey)
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(descriptionKey)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

#Preview {
    RootView(context: PersistenceController.preview.container.viewContext)
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
