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
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject var repositoryManager: RepositoryManager
    @StateObject private var selectionStore = AppNavigationSelectionStore()
    @StateObject private var tabStateManager = WorktreeTabStateStore()
    @StateObject private var navigator = AppWorktreeNavigator()

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Workspace.order, ascending: true)],
        animation: .default)
    private var workspaces: FetchedResults<Workspace>

    @State private var searchText = ""
    @State private var showingAddRepository = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @AppStorage("hasShownOnboarding") private var hasShownOnboarding = false
    @AppStorage("hasShownCrossProjectOnboarding") private var hasShownCrossProjectOnboarding = false
    @State private var showingOnboarding = false
    @State private var showingCrossProjectOnboarding = false
    @AppStorage("zenModeEnabled") private var zenModeEnabled = false

    @State private var saveTask: Task<Void, Never>?

    // Git changes overlay state (passed from RootView)
    @Binding var gitChangesContext: GitChangesContext?

    // Persistent selection storage
    @AppStorage("selectedWorkspaceId") private var selectedWorkspaceId: String?
    @AppStorage("selectedRepositoryId") private var selectedRepositoryId: String?
    @AppStorage("selectedWorktreeId") private var selectedWorktreeId: String?
    @AppStorage("selectedWorktreeByRepository") private var selectedWorktreeByRepositoryData: String = "{}"
    @AppStorage("worktreeMRUOrder") private var worktreeMRUOrderData: String = "[]"
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

    private func isCrossProjectRepository(_ repository: Repository) -> Bool {
        repository.isCrossProject || repository.note == crossProjectRepositoryMarker
    }

    private func visibleRepositories(in workspace: Workspace) -> [Repository] {
        let repositories = (workspace.repositories as? Set<Repository>) ?? []
        return repositories
            .filter { !$0.isDeleted && !isCrossProjectRepository($0) }
            .sorted { ($0.name ?? "") < ($1.name ?? "") }
    }

    private func ensureCrossProjectWorktree(for workspace: Workspace) throws -> Worktree {
        try CrossProjectWorkspaceCoordinator(
            viewContext: viewContext,
            repositoryMarker: crossProjectRepositoryMarker
        )
        .ensureWorktree(
            for: workspace,
            visibleRepositories: visibleRepositories(in: workspace)
        )
    }

    private func prepareCrossProjectWorkspaceIfNeeded() {
        guard selectionStore.isCrossProjectSelected, let workspace = selectionStore.selectedWorkspace else {
            selectCrossProjectWorktree(nil)
            return
        }

        do {
            selectCrossProjectWorktree(try ensureCrossProjectWorktree(for: workspace))
        } catch {
            selectCrossProjectWorktree(nil)
        }
    }

    private func presentCrossProjectOnboardingIfNeeded() {
        guard !hasShownCrossProjectOnboarding else {
            return
        }

        hasShownCrossProjectOnboarding = true
        showingCrossProjectOnboarding = true
    }

    private func showCommandPalette() {
        let activeWorktree = currentActiveWorktree()
        let currentRepositoryId = selectionStore.selectedRepository?.id?.uuidString
            ?? activeWorktree?.repository?.id?.uuidString
        let currentWorkspaceId = selectionStore.selectedWorkspace?.id?.uuidString
            ?? activeWorktree?.repository?.workspace?.id?.uuidString

        navigator.showCommandPalette(
            viewContext: viewContext,
            currentRepositoryId: currentRepositoryId,
            currentWorkspaceId: currentWorkspaceId,
            onNavigate: { action in
                navigator.handleCommandPaletteNavigation(action, navigateToWorktree: navigateToWorktree)
            }
        )
    }

    private func currentActiveWorktree() -> Worktree? {
        if selectionStore.isCrossProjectSelected {
            return selectionStore.crossProjectWorktree
        }
        return selectionStore.selectedWorktree
    }

    private func decodeSelectedWorktreeByRepository() -> [String: String] {
        WorktreeSelectionPersistence.decodeRepositorySelections(from: selectedWorktreeByRepositoryData)
    }

    private func encodeSelectedWorktreeByRepository(_ map: [String: String]) {
        guard let json = WorktreeSelectionPersistence.encodeRepositorySelections(map) else {
            return
        }
        selectedWorktreeByRepositoryData = json
    }

    private func getStoredWorktreeId(for repository: Repository) -> UUID? {
        guard let repositoryId = repository.id?.uuidString else { return nil }
        return WorktreeSelectionPersistence.storedWorktreeId(
            for: repositoryId,
            repositorySelectionsJSON: selectedWorktreeByRepositoryData
        )
    }

    private func storeWorktreeSelection(_ worktreeId: UUID?, for repository: Repository) {
        guard let repositoryId = repository.id?.uuidString else { return }
        guard let json = WorktreeSelectionPersistence.updatingRepositorySelectionsJSON(
            repositorySelectionsJSON: selectedWorktreeByRepositoryData,
            repositoryId: repositoryId,
            worktreeId: worktreeId
        ) else {
            return
        }
        selectedWorktreeByRepositoryData = json
    }

    private func decodeWorktreeMRUOrder() -> [String] {
        WorktreeSelectionPersistence.decodeMRUOrder(from: worktreeMRUOrderData)
    }

    private func encodeWorktreeMRUOrder(_ order: [String]) {
        guard let json = WorktreeSelectionPersistence.encodeMRUOrder(order) else {
            return
        }
        worktreeMRUOrderData = json
    }

    private func recordWorktreeInMRU(_ worktree: Worktree) {
        guard !worktree.isDeleted, let worktreeId = worktree.id?.uuidString else {
            return
        }

        var order = decodeWorktreeMRUOrder()
        order.removeAll { $0 == worktreeId }
        order.insert(worktreeId, at: 0)

        if order.count > 100 {
            order = Array(order.prefix(100))
        }

        encodeWorktreeMRUOrder(order)
    }

    private func quickSwitchToPreviousWorktree() {
        let request: NSFetchRequest<Worktree> = Worktree.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Worktree.lastAccessed, ascending: false)]

        guard let fetchedWorktrees = try? viewContext.fetch(request) else { return }

        guard let target = WorktreeQuickSwitcher.nextTarget(
            from: fetchedWorktrees,
            currentWorktreeId: currentActiveWorktree()?.id?.uuidString,
            mruOrder: decodeWorktreeMRUOrder()
        ) else {
            return
        }

        encodeWorktreeMRUOrder(target.updatedMRUOrder)

        guard let selectedTarget = fetchedWorktrees.first(where: { $0.id == target.worktreeId }) else {
            return
        }

        selectedTarget.lastAccessed = Date()
        try? viewContext.save()
        navigateToWorktree(
            workspaceId: target.workspaceId,
            repoId: target.repositoryId,
            worktreeId: target.worktreeId
        )
    }

    private func navigateToWorktree(workspaceId: UUID, repoId: UUID, worktreeId: UUID) {
        guard let workspace = workspaces.first(where: { $0.id == workspaceId }) else {
            return
        }

        selectWorkspace(workspace, preserveSelection: true)

        let allRepositories = (workspace.repositories as? Set<Repository>) ?? []
        let allWorkspaceWorktrees = allRepositories.flatMap { (repository) -> [Worktree] in
            ((repository.worktrees as? Set<Worktree>) ?? []).filter { !$0.isDeleted }
        }

        if let targetWorktree = allWorkspaceWorktrees.first(where: { $0.id == worktreeId }),
           let targetRepository = targetWorktree.repository {
            if isCrossProjectRepository(targetRepository) {
                setCrossProjectSelected(true, preferredWorktree: targetWorktree)
                return
            }

            selectRepository(targetRepository)
            selectWorktree(targetWorktree)
            return
        }

        if let crossProjectRepository = allRepositories.first(where: { $0.id == repoId && isCrossProjectRepository($0) }) {
            let worktrees = (crossProjectRepository.worktrees as? Set<Worktree>) ?? []
            if let worktree = worktrees.first(where: { $0.id == worktreeId && !$0.isDeleted }) {
                setCrossProjectSelected(true, preferredWorktree: worktree)
            } else {
                setCrossProjectSelected(true)
            }
            return
        }

        let repositories = visibleRepositories(in: workspace)
        if let repository = repositories.first(where: { $0.id == repoId }) {
            selectRepository(repository)
            let worktrees = (repository.worktrees as? Set<Worktree>) ?? []
            if let worktree = worktrees.first(where: { $0.id == worktreeId }) {
                selectWorktree(worktree)
            }
        }
    }

    private func selectWorkspace(_ workspace: Workspace?, preserveSelection: Bool = false) {
        selectionStore.selectedWorkspace = workspace
        selectedWorkspaceId = workspace?.id?.uuidString

        if preserveSelection {
            return
        }

        if selectionStore.suppressWorkspaceAutoSelection {
            selectionStore.suppressWorkspaceAutoSelection = false
            return
        }

        if selectionStore.isCrossProjectSelected {
            setCrossProjectSelected(false)
        }

        guard let workspace else {
            selectRepository(nil)
            return
        }

        let repositories = visibleRepositories(in: workspace)
        if let lastRepoId = workspace.lastSelectedRepositoryId,
           let lastRepo = repositories.first(where: { $0.id == lastRepoId }) {
            selectRepository(lastRepo)
        } else {
            selectRepository(repositories.first)
        }
    }

    private func selectRepository(_ repository: Repository?) {
        selectionStore.selectedRepository = repository
        selectedRepositoryId = repository?.id?.uuidString

        guard let repository else {
            selectWorktree(nil)
            return
        }

        if isCrossProjectRepository(repository) {
            selectionStore.selectedRepository = nil
            selectedRepositoryId = nil
            setCrossProjectSelected(true)
            return
        }

        if repository.isDeleted || repository.isFault {
            selectionStore.selectedRepository = nil
            selectedRepositoryId = nil
            selectWorktree(nil)
            return
        }

        if selectionStore.isCrossProjectSelected {
            setCrossProjectSelected(false)
        }

        if let workspace = selectionStore.selectedWorkspace {
            workspace.lastSelectedRepositoryId = repository.id
            saveTask?.cancel()
            saveTask = Task {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                try? viewContext.save()
            }
        }

        let worktrees = (repository.worktrees as? Set<Worktree>) ?? []
        if let restoredWorktreeId = getStoredWorktreeId(for: repository),
           let restoredWorktree = worktrees.first(where: { $0.id == restoredWorktreeId && !$0.isDeleted }) {
            selectWorktree(restoredWorktree)
            return
        }

        if let worktreeId = selectedWorktreeId,
           let uuid = UUID(uuidString: worktreeId),
           let restoredWorktree = worktrees.first(where: { $0.id == uuid && !$0.isDeleted }) {
            selectWorktree(restoredWorktree)
            return
        }

        let candidates = worktrees.filter { !$0.isDeleted }
        selectWorktree(candidates.first(where: { $0.isPrimary }) ?? candidates.first)
    }

    private func selectWorktree(_ worktree: Worktree?) {
        if let worktree, worktree.isDeleted {
            selectionStore.selectedWorktree = nil
            selectedWorktreeId = nil
            if let repository = selectionStore.selectedRepository {
                let worktrees = (repository.worktrees as? Set<Worktree>) ?? []
                let fallback = worktrees.first(where: { $0.isPrimary && !$0.isDeleted })
                if let fallback {
                    selectWorktree(fallback)
                }
            }
            return
        }

        selectionStore.selectedWorktree = worktree
        selectedWorktreeId = worktree?.id?.uuidString

        guard let worktree else { return }

        recordWorktreeInMRU(worktree)
        if let repository = selectionStore.selectedRepository {
            storeWorktreeSelection(worktree.id, for: repository)
        }
        Task { @MainActor in
            try? repositoryManager.updateWorktreeAccess(worktree)
        }
    }

    private func selectCrossProjectWorktree(_ worktree: Worktree?) {
        selectionStore.crossProjectWorktree = worktree
        guard selectionStore.isCrossProjectSelected, let worktree, !worktree.isDeleted else {
            return
        }
        recordWorktreeInMRU(worktree)
    }

    private func setCrossProjectSelected(_ isSelected: Bool, preferredWorktree: Worktree? = nil) {
        if !isSelected {
            selectionStore.isCrossProjectSelected = false
            if let previousZenMode = selectionStore.zenModeBeforeCrossProjectSelection {
                zenModeEnabled = previousZenMode
                selectionStore.zenModeBeforeCrossProjectSelection = nil
            }
            selectCrossProjectWorktree(nil)
            return
        }

        if selectionStore.zenModeBeforeCrossProjectSelection == nil {
            selectionStore.zenModeBeforeCrossProjectSelection = zenModeEnabled
        }

        selectionStore.isCrossProjectSelected = true
        zenModeEnabled = true
        selectionStore.selectedRepository = nil
        selectedRepositoryId = nil
        selectionStore.selectedWorktree = nil
        selectedWorktreeId = nil

        if let preferredWorktree, !preferredWorktree.isDeleted {
            selectCrossProjectWorktree(preferredWorktree)
        } else {
            prepareCrossProjectWorkspaceIfNeeded()
        }

        presentCrossProjectOnboardingIfNeeded()
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
