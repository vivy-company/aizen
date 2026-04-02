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
    @StateObject private var tabStateManager = WorktreeTabStateStore()
    @StateObject private var navigator = AppWorktreeNavigator()

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Workspace.order, ascending: true)],
        animation: .default)
    var workspaces: FetchedResults<Workspace>

    @State private var searchText = ""
    @State private var showingAddRepository = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @AppStorage("hasShownOnboarding") private var hasShownOnboarding = false
    @AppStorage("hasShownCrossProjectOnboarding") private var hasShownCrossProjectOnboarding = false
    @State private var showingOnboarding = false
    @State private var showingCrossProjectOnboarding = false
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
    private let crossProjectRepositoryMarker = "__aizen.cross_project.workspace_repo__"

    init(context: NSManagedObjectContext, repositoryManager: RepositoryManager, gitChangesContext: Binding<GitChangesContext?>) {
        self.repositoryManager = repositoryManager
        _gitChangesContext = gitChangesContext
    }

    private var selectedWorkspaceBinding: Binding<Workspace?> {
        Binding(
            get: { selectionStore.selectedWorkspace },
            set: { selectWorkspace($0) }
        )
    }

    private var crossProjectSelectionBinding: Binding<Bool> {
        Binding(
            get: { selectionStore.isCrossProjectSelected },
            set: { setCrossProjectSelected($0) }
        )
    }

    private var selectedRepositoryBinding: Binding<Repository?> {
        Binding(
            get: { selectionStore.selectedRepository },
            set: { selectRepository($0) }
        )
    }

    private var selectedWorktreeBinding: Binding<Worktree?> {
        Binding(
            get: { selectionStore.selectedWorktree },
            set: { selectWorktree($0) }
        )
    }

    var body: some View {
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
        .onAppear {
            if selectionStore.isCrossProjectSelected && selectionStore.crossProjectWorktree == nil {
                setCrossProjectSelected(false)
            }

            // Restore selected workspace from persistent storage
            if selectionStore.selectedWorkspace == nil {
                if let workspaceId = selectedWorkspaceId,
                   let uuid = UUID(uuidString: workspaceId),
                   let workspace = workspaces.first(where: { $0.id == uuid }) {
                    selectWorkspace(workspace)
                } else {
                    selectWorkspace(workspaces.first)
                }
            }

            if !hasShownOnboarding {
                showingOnboarding = true
                hasShownOnboarding = true
            }
        }
        .task(id: zenModeEnabled) {
            if selectionStore.isCrossProjectSelected && !zenModeEnabled {
                zenModeEnabled = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .commandPaletteShortcut)) { _ in
            showCommandPalette()
        }
        .onReceive(NotificationCenter.default.publisher(for: .quickSwitchWorktree)) { _ in
            quickSwitchToPreviousWorktree()
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToWorktree)) { notification in
            guard let info = notification.userInfo,
                  let workspaceId = info["workspaceId"] as? UUID,
                  let repoId = info["repoId"] as? UUID,
                  let worktreeId = info["worktreeId"] as? UUID else {
                return
            }
            navigateToWorktree(workspaceId: workspaceId, repoId: repoId, worktreeId: worktreeId)
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToChatSession)) { notification in
            guard let chatSessionId = notification.userInfo?["chatSessionId"] as? UUID else {
                return
            }
            navigator.navigateToChatSession(
                chatSessionId: chatSessionId,
                viewContext: viewContext,
                navigateToWorktree: navigateToWorktree
            )
        }
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
