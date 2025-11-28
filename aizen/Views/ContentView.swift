//
//  ContentView.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import SwiftUI
import CoreData

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var repositoryManager: RepositoryManager
    @StateObject private var tabStateManager = WorktreeTabStateManager()

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Workspace.order, ascending: true)],
        animation: .default)
    private var workspaces: FetchedResults<Workspace>

    @State private var selectedWorkspace: Workspace?
    @State private var selectedRepository: Repository?
    @State private var selectedWorktree: Worktree?
    @State private var searchText = ""
    @State private var showingAddRepository = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var previousWorktree: Worktree?
    @AppStorage("hasShownOnboarding") private var hasShownOnboarding = false
    @State private var showingOnboarding = false
    @AppStorage("zenModeEnabled") private var zenModeEnabled = false

    // Command palette state
    @State private var commandPaletteController: CommandPaletteWindowController?

    // Persistent selection storage
    @AppStorage("selectedWorkspaceId") private var selectedWorkspaceId: String?
    @AppStorage("selectedRepositoryId") private var selectedRepositoryId: String?
    @AppStorage("selectedWorktreeId") private var selectedWorktreeId: String?

    init(context: NSManagedObjectContext) {
        _repositoryManager = StateObject(wrappedValue: RepositoryManager(viewContext: context))
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Left sidebar - workspaces and repositories
            WorkspaceSidebarView(
                workspaces: Array(workspaces),
                selectedWorkspace: $selectedWorkspace,
                selectedRepository: $selectedRepository,
                selectedWorktree: $selectedWorktree,
                searchText: $searchText,
                showingAddRepository: $showingAddRepository,
                repositoryManager: repositoryManager
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 300)
        } content: {
            // Middle panel - worktree list or detail
            Group {
                if let repository = selectedRepository {
                    WorktreeListView(
                        repository: repository,
                        selectedWorktree: $selectedWorktree,
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
            if let worktree = selectedWorktree, !worktree.isDeleted {
                WorktreeDetailView(
                    worktree: worktree,
                    repositoryManager: repositoryManager,
                    tabStateManager: tabStateManager,
                    onWorktreeDeleted: { nextWorktree in
                        selectedWorktree = nextWorktree
                    }
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
            if let workspace = selectedWorkspace ?? workspaces.first {
                RepositoryAddSheet(
                    workspace: workspace,
                    repositoryManager: repositoryManager,
                    onRepositoryAdded: { repository in
                        selectedWorktree = nil
                        selectedRepository = repository
                    }
                )
            }
        }
        .sheet(isPresented: $showingOnboarding) {
            OnboardingView()
        }
        .onAppear {
            // Restore selected workspace from persistent storage
            if selectedWorkspace == nil {
                if let workspaceId = selectedWorkspaceId,
                   let uuid = UUID(uuidString: workspaceId),
                   let workspace = workspaces.first(where: { $0.id == uuid }) {
                    selectedWorkspace = workspace
                } else {
                    selectedWorkspace = workspaces.first
                }
            }

            // Restore selected repository from persistent storage
            if selectedRepository == nil,
               let repositoryId = selectedRepositoryId,
               let uuid = UUID(uuidString: repositoryId),
               let workspace = selectedWorkspace {
                let repositories = (workspace.repositories as? Set<Repository>) ?? []
                selectedRepository = repositories.first(where: { $0.id == uuid })
            }

            // Restore selected worktree from persistent storage
            if selectedWorktree == nil,
               let worktreeId = selectedWorktreeId,
               let uuid = UUID(uuidString: worktreeId),
               let repository = selectedRepository {
                let worktrees = (repository.worktrees as? Set<Worktree>) ?? []
                selectedWorktree = worktrees.first(where: { $0.id == uuid })
            }

            if !hasShownOnboarding {
                showingOnboarding = true
                hasShownOnboarding = true
            }
        }
        .onChange(of: selectedWorkspace) { newValue in
            selectedWorkspaceId = newValue?.id?.uuidString
        }
        .onChange(of: selectedRepository) { newValue in
            selectedRepositoryId = newValue?.id?.uuidString

            if let repo = newValue, repo.isDeleted || repo.isFault {
                selectedRepository = nil
                selectedWorktree = nil
            } else if let repo = newValue {
                // Auto-select primary worktree when repository changes
                let worktrees = (repo.worktrees as? Set<Worktree>) ?? []
                selectedWorktree = worktrees.first(where: { $0.isPrimary })
            }
        }
        .onChange(of: selectedWorktree) { newValue in
            selectedWorktreeId = newValue?.id?.uuidString

            if let newWorktree = newValue, !newWorktree.isDeleted {
                previousWorktree = newWorktree
            } else if newValue?.isDeleted == true {
                // Worktree was deleted, fall back to primary worktree
                selectedWorktree = nil
                if let repository = selectedRepository {
                    let worktrees = (repository.worktrees as? Set<Worktree>) ?? []
                    selectedWorktree = worktrees.first(where: { $0.isPrimary && !$0.isDeleted })
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .commandPaletteShortcut)) { _ in
            showCommandPalette()
        }
    }

    private func showCommandPalette() {
        let controller = CommandPaletteWindowController(
            managedObjectContext: viewContext,
            onNavigate: { workspaceId, repoId, worktreeId in
                navigateToWorktree(workspaceId: workspaceId, repoId: repoId, worktreeId: worktreeId)
            }
        )
        commandPaletteController = controller
        controller.showWindow(nil)
    }

    private func navigateToWorktree(workspaceId: UUID, repoId: UUID, worktreeId: UUID) {
        if let workspace = workspaces.first(where: { $0.id == workspaceId }) {
            selectedWorkspace = workspace
            let repos = (workspace.repositories as? Set<Repository>) ?? []
            if let repo = repos.first(where: { $0.id == repoId }) {
                selectedRepository = repo
                let worktrees = (repo.worktrees as? Set<Worktree>) ?? []
                if let worktree = worktrees.first(where: { $0.id == worktreeId }) {
                    selectedWorktree = worktree
                }
            }
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
    ContentView(context: PersistenceController.preview.container.viewContext)
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
