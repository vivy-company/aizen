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
                // Middle panel - worktree list or detail
                Group {
                    if selectionStore.isCrossProjectSelected {
                        Color.clear
                    } else if let repository = selectionStore.selectedRepository {
                        WorktreeListView(
                            repository: repository,
                            selectedWorktree: selectedWorktreeBinding,
                            repositoryManager: repositoryManager,
                            tabStateManager: tabStateManager
                        )
                    } else {
                        placeholderView(
                            titleKey: "contentView.selectRepository",
                            systemImage: "folder.badge.gearshape",
                            descriptionKey: "contentView.selectRepositoryDescription"
                        )
                    }
                }
                .navigationSplitViewColumnWidth(
                    min: zenModeEnabled ? 0 : 250,
                    ideal: zenModeEnabled ? 0 : 300,
                    max: zenModeEnabled ? 0 : 400
                )
                .opacity(zenModeEnabled ? 0 : 1)
                .allowsHitTesting(!zenModeEnabled)
                .animation(.easeInOut(duration: 0.25), value: zenModeEnabled)
            } detail: {
                // Right panel - worktree details
                if selectionStore.isCrossProjectSelected, let worktree = selectionStore.crossProjectWorktree, !worktree.isDeleted {
                    WorktreeDetailView(
                        worktree: worktree,
                        repositoryManager: repositoryManager,
                        tabStateManager: tabStateManager,
                        gitChangesContext: $gitChangesContext,
                        onWorktreeDeleted: { _ in
                            selectCrossProjectWorktree(nil)
                            prepareCrossProjectWorkspaceIfNeeded()
                        },
                        showZenModeButton: false
                    )
                    .id(worktree.id)
                } else if selectionStore.isCrossProjectSelected {
                    Color.clear
                        .task {
                            prepareCrossProjectWorkspaceIfNeeded()
                        }
                } else if let worktree = selectionStore.selectedWorktree, !worktree.isDeleted {
                    WorktreeDetailView(
                        worktree: worktree,
                        repositoryManager: repositoryManager,
                        tabStateManager: tabStateManager,
                        gitChangesContext: $gitChangesContext,
                        onWorktreeDeleted: { nextWorktree in
                            selectWorktree(nextWorktree)
                        },
                        showZenModeButton: true
                    )
                    .id(worktree.id)
                } else {
                    placeholderView(
                        titleKey: "contentView.selectWorktree",
                        systemImage: "arrow.triangle.branch",
                        descriptionKey: "contentView.selectWorktreeDescription"
                    )
                }
            }
            .sheet(isPresented: $showingAddRepository) {
                if let workspace = selectionStore.selectedWorkspace ?? workspaces.first {
                    RepositoryAddSheet(
                        workspace: workspace,
                        repositoryManager: repositoryManager,
                        onRepositoryAdded: { repository in
                            selectRepository(repository)
                        }
                    )
                }
            }
            .sheet(isPresented: $showingOnboarding) {
                OnboardingView()
            }
            .sheet(isPresented: $showingCrossProjectOnboarding) {
                CrossProjectOnboardingView()
            }
        )
    }

}



@ViewBuilder
private func placeholderView(
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
