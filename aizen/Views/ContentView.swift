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
    @StateObject private var tabStateManager = WorktreeTabStateStore()
    @StateObject private var navigator = AppWorktreeNavigator()

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Workspace.order, ascending: true)],
        animation: .default)
    private var workspaces: FetchedResults<Workspace>

    @State private var selectedWorkspace: Workspace?
    @State private var isCrossProjectSelected = false
    @State private var selectedRepository: Repository?
    @State private var selectedWorktree: Worktree?
    @State private var crossProjectWorktree: Worktree?
    @State private var searchText = ""
    @State private var showingAddRepository = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var zenModeBeforeCrossProjectSelection: Bool?
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
    @State private var suppressWorkspaceAutoSelection = false
    private let crossProjectRepositoryMarker = "__aizen.cross_project.workspace_repo__"

    init(context: NSManagedObjectContext, repositoryManager: RepositoryManager, gitChangesContext: Binding<GitChangesContext?>) {
        self.repositoryManager = repositoryManager
        _gitChangesContext = gitChangesContext
    }

    private var selectedWorkspaceBinding: Binding<Workspace?> {
        Binding(
            get: { selectedWorkspace },
            set: { selectWorkspace($0) }
        )
    }

    private var crossProjectSelectionBinding: Binding<Bool> {
        Binding(
            get: { isCrossProjectSelected },
            set: { setCrossProjectSelected($0) }
        )
    }

    private var selectedRepositoryBinding: Binding<Repository?> {
        Binding(
            get: { selectedRepository },
            set: { selectRepository($0) }
        )
    }

    private var selectedWorktreeBinding: Binding<Worktree?> {
        Binding(
            get: { selectedWorktree },
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
                if isCrossProjectSelected {
                    Color.clear
                } else if let repository = selectedRepository {
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
            if isCrossProjectSelected, let worktree = crossProjectWorktree, !worktree.isDeleted {
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
            } else if isCrossProjectSelected {
                Color.clear
                    .task {
                        prepareCrossProjectWorkspaceIfNeeded()
                    }
            } else if let worktree = selectedWorktree, !worktree.isDeleted {
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
            if let workspace = selectedWorkspace ?? workspaces.first {
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
            if isCrossProjectSelected && crossProjectWorktree == nil {
                setCrossProjectSelected(false)
            }

            // Restore selected workspace from persistent storage
            if selectedWorkspace == nil {
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
            if isCrossProjectSelected && !zenModeEnabled {
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

    private func crossProjectRootURL(for workspace: Workspace) throws -> URL {
        guard let workspaceId = workspace.id else {
            throw NSError(domain: "AizenCrossProject", code: 1, userInfo: [NSLocalizedDescriptionKey: "Workspace identifier is missing"])
        }

        let workspaceRequest: NSFetchRequest<Workspace> = Workspace.fetchRequest()
        let allWorkspaces = try viewContext.fetch(workspaceRequest)
        let candidates = allWorkspaces.compactMap { candidate -> WorkspacePathCandidate? in
            guard let candidateID = candidate.id else {
                return nil
            }
            return WorkspacePathCandidate(id: candidateID, name: candidate.name)
        }

        return CrossProjectWorkspacePath.rootURL(
            for: workspaceId,
            workspaceName: workspace.name,
            allWorkspaces: candidates
        )
    }

    private func prepareCrossProjectDirectory(for workspace: Workspace) throws -> URL {
        let fileManager = FileManager.default
        let rootURL = try crossProjectRootURL(for: workspace)

        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let existingItems = try fileManager.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil)
        for itemURL in existingItems {
            try? fileManager.removeItem(at: itemURL)
        }

        var usedNames = Set<String>()
        for repository in visibleRepositories(in: workspace) {
            guard let sourcePath = repository.path, fileManager.fileExists(atPath: sourcePath) else {
                continue
            }

            let fallbackName = URL(fileURLWithPath: sourcePath).lastPathComponent
            let rawName = (repository.name?.isEmpty == false ? repository.name! : fallbackName)
            let sanitizedName = rawName
                .replacingOccurrences(of: "/", with: "-")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let baseName = sanitizedName.isEmpty ? "project" : sanitizedName

            var linkName = baseName
            var suffix = 2
            while usedNames.contains(linkName) {
                linkName = "\(baseName)-\(suffix)"
                suffix += 1
            }
            usedNames.insert(linkName)

            let linkPath = rootURL.appendingPathComponent(linkName).path
            if fileManager.fileExists(atPath: linkPath) {
                try? fileManager.removeItem(atPath: linkPath)
            }

            try fileManager.createSymbolicLink(atPath: linkPath, withDestinationPath: sourcePath)
        }

        return rootURL
    }

    private func ensureCrossProjectWorktree(for workspace: Workspace) throws -> Worktree {
        let rootURL = try prepareCrossProjectDirectory(for: workspace)

        let repositoryRequest: NSFetchRequest<Repository> = Repository.fetchRequest()
        repositoryRequest.fetchLimit = 1
        repositoryRequest.predicate = NSPredicate(
            format: "workspace == %@ AND (isCrossProject == YES OR note == %@)",
            workspace,
            crossProjectRepositoryMarker
        )

        let repository = try viewContext.fetch(repositoryRequest).first ?? Repository(context: viewContext)
        if repository.id == nil {
            repository.id = UUID()
        }
        repository.name = "Cross-Project"
        repository.path = rootURL.path
        repository.note = crossProjectRepositoryMarker
        repository.isCrossProject = true
        repository.status = "active"
        repository.workspace = workspace
        repository.lastUpdated = Date()

        let existingWorktrees = ((repository.worktrees as? Set<Worktree>) ?? []).filter { !$0.isDeleted }
        let worktree = existingWorktrees.first(where: { $0.isPrimary }) ?? existingWorktrees.first ?? Worktree(context: viewContext)
        if worktree.id == nil {
            worktree.id = UUID()
        }
        worktree.path = rootURL.path
        worktree.branch = "workspace"
        worktree.isPrimary = true
        worktree.checkoutTypeValue = .primary
        worktree.repository = repository
        worktree.lastAccessed = Date()

        try viewContext.save()
        return worktree
    }

    private func prepareCrossProjectWorkspaceIfNeeded() {
        guard isCrossProjectSelected, let workspace = selectedWorkspace else {
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
        let currentRepositoryId = selectedRepository?.id?.uuidString
            ?? activeWorktree?.repository?.id?.uuidString
        let currentWorkspaceId = selectedWorkspace?.id?.uuidString
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
        if isCrossProjectSelected {
            return crossProjectWorktree
        }
        return selectedWorktree
    }

    private func decodeSelectedWorktreeByRepository() -> [String: String] {
        guard let data = selectedWorktreeByRepositoryData.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private func encodeSelectedWorktreeByRepository(_ map: [String: String]) {
        guard let encoded = try? JSONEncoder().encode(map),
              let json = String(data: encoded, encoding: .utf8) else {
            return
        }
        selectedWorktreeByRepositoryData = json
    }

    private func getStoredWorktreeId(for repository: Repository) -> UUID? {
        guard let repositoryId = repository.id?.uuidString else { return nil }
        let map = decodeSelectedWorktreeByRepository()
        guard let worktreeIdString = map[repositoryId] else { return nil }
        return UUID(uuidString: worktreeIdString)
    }

    private func storeWorktreeSelection(_ worktreeId: UUID?, for repository: Repository) {
        guard let repositoryId = repository.id?.uuidString else { return }
        var map = decodeSelectedWorktreeByRepository()
        if let worktreeId {
            map[repositoryId] = worktreeId.uuidString
        } else {
            map.removeValue(forKey: repositoryId)
        }
        encodeSelectedWorktreeByRepository(map)
    }

    private func decodeWorktreeMRUOrder() -> [String] {
        guard let data = worktreeMRUOrderData.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return decoded
    }

    private func encodeWorktreeMRUOrder(_ order: [String]) {
        guard let encoded = try? JSONEncoder().encode(order),
              let json = String(data: encoded, encoding: .utf8) else {
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

    private func sanitizedMRUOrder(with availableById: [String: Worktree], currentId: String?) -> [String] {
        var cleaned: [String] = []
        var seen = Set<String>()

        for id in decodeWorktreeMRUOrder() where availableById[id] != nil {
            if seen.insert(id).inserted {
                cleaned.append(id)
            }
        }

        if let currentId,
           availableById[currentId] != nil,
           !cleaned.contains(currentId) {
            cleaned.insert(currentId, at: 0)
        }

        encodeWorktreeMRUOrder(cleaned)
        return cleaned
    }

    private func quickSwitchToPreviousWorktree() {
        let request: NSFetchRequest<Worktree> = Worktree.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Worktree.lastAccessed, ascending: false)]

        guard let fetchedWorktrees = try? viewContext.fetch(request) else { return }

        let available = fetchedWorktrees.filter { worktree in
            guard !worktree.isDeleted else { return false }
            guard worktree.id != nil else { return false }
            guard worktree.repository?.id != nil else { return false }
            guard worktree.repository?.workspace?.id != nil else { return false }
            return true
        }

        let availableById: [String: Worktree] = Dictionary(
            uniqueKeysWithValues: available.compactMap { worktree in
                guard let id = worktree.id?.uuidString else { return nil }
                return (id, worktree)
            }
        )

        let currentId = currentActiveWorktree()?.id?.uuidString
        let mruOrder = sanitizedMRUOrder(with: availableById, currentId: currentId)

        let targetId: String?
        if let currentId,
           mruOrder.first == currentId {
            targetId = mruOrder.dropFirst().first
        } else {
            targetId = mruOrder.first(where: { $0 != currentId })
        }

        guard let resolvedTargetId = targetId ?? available.first(where: { $0.id?.uuidString != currentId })?.id?.uuidString,
              let target = availableById[resolvedTargetId],
              let worktreeId = target.id,
              let repoId = target.repository?.id,
              let workspaceId = target.repository?.workspace?.id else {
            return
        }

        target.lastAccessed = Date()
        try? viewContext.save()
        navigateToWorktree(workspaceId: workspaceId, repoId: repoId, worktreeId: worktreeId)
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
        selectedWorkspace = workspace
        selectedWorkspaceId = workspace?.id?.uuidString

        if preserveSelection {
            return
        }

        if suppressWorkspaceAutoSelection {
            suppressWorkspaceAutoSelection = false
            return
        }

        if isCrossProjectSelected {
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
        selectedRepository = repository
        selectedRepositoryId = repository?.id?.uuidString

        guard let repository else {
            selectWorktree(nil)
            return
        }

        if isCrossProjectRepository(repository) {
            selectedRepository = nil
            selectedRepositoryId = nil
            setCrossProjectSelected(true)
            return
        }

        if repository.isDeleted || repository.isFault {
            selectedRepository = nil
            selectedRepositoryId = nil
            selectWorktree(nil)
            return
        }

        if isCrossProjectSelected {
            setCrossProjectSelected(false)
        }

        if let workspace = selectedWorkspace {
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
            selectedWorktree = nil
            selectedWorktreeId = nil
            if let repository = selectedRepository {
                let worktrees = (repository.worktrees as? Set<Worktree>) ?? []
                let fallback = worktrees.first(where: { $0.isPrimary && !$0.isDeleted })
                if let fallback {
                    selectWorktree(fallback)
                }
            }
            return
        }

        selectedWorktree = worktree
        selectedWorktreeId = worktree?.id?.uuidString

        guard let worktree else { return }

        recordWorktreeInMRU(worktree)
        if let repository = selectedRepository {
            storeWorktreeSelection(worktree.id, for: repository)
        }
        Task { @MainActor in
            try? repositoryManager.updateWorktreeAccess(worktree)
        }
    }

    private func selectCrossProjectWorktree(_ worktree: Worktree?) {
        crossProjectWorktree = worktree
        guard isCrossProjectSelected, let worktree, !worktree.isDeleted else {
            return
        }
        recordWorktreeInMRU(worktree)
    }

    private func setCrossProjectSelected(_ isSelected: Bool, preferredWorktree: Worktree? = nil) {
        if !isSelected {
            isCrossProjectSelected = false
            if let previousZenMode = zenModeBeforeCrossProjectSelection {
                zenModeEnabled = previousZenMode
                zenModeBeforeCrossProjectSelection = nil
            }
            selectCrossProjectWorktree(nil)
            return
        }

        if zenModeBeforeCrossProjectSelection == nil {
            zenModeBeforeCrossProjectSelection = zenModeEnabled
        }

        isCrossProjectSelected = true
        zenModeEnabled = true
        selectedRepository = nil
        selectedRepositoryId = nil
        selectedWorktree = nil
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
