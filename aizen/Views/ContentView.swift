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
    @StateObject private var tabStateManager = WorktreeTabStateManager()

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
    @State private var previousWorktree: Worktree?
    @State private var zenModeBeforeCrossProjectSelection: Bool?
    @AppStorage("hasShownOnboarding") private var hasShownOnboarding = false
    @State private var showingOnboarding = false
    @AppStorage("zenModeEnabled") private var zenModeEnabled = false

    // Command palette state
    @State private var commandPaletteController: CommandPaletteWindowController?
    @State private var saveTask: Task<Void, Never>?

    // Git changes overlay state (passed from RootView)
    @Binding var gitChangesContext: GitChangesContext?

    // Persistent selection storage
    @AppStorage("selectedWorkspaceId") private var selectedWorkspaceId: String?
    @AppStorage("selectedRepositoryId") private var selectedRepositoryId: String?
    @AppStorage("selectedWorktreeId") private var selectedWorktreeId: String?
    @AppStorage("selectedWorktreeByRepository") private var selectedWorktreeByRepositoryData: String = "{}"
    private let crossProjectRepositoryMarker = "__aizen.cross_project.workspace_repo__"

    init(context: NSManagedObjectContext, repositoryManager: RepositoryManager, gitChangesContext: Binding<GitChangesContext?>) {
        self.repositoryManager = repositoryManager
        _gitChangesContext = gitChangesContext
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Left sidebar - workspaces and repositories
            WorkspaceSidebarView(
                workspaces: Array(workspaces),
                selectedWorkspace: $selectedWorkspace,
                isCrossProjectSelected: $isCrossProjectSelected,
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
                if isCrossProjectSelected {
                    Color.clear
                } else if let repository = selectedRepository {
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
            if isCrossProjectSelected, let worktree = crossProjectWorktree, !worktree.isDeleted {
                WorktreeDetailView(
                    worktree: worktree,
                    repositoryManager: repositoryManager,
                    tabStateManager: tabStateManager,
                    gitChangesContext: $gitChangesContext,
                    onWorktreeDeleted: { _ in
                        crossProjectWorktree = nil
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
                        selectedWorktree = nextWorktree
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
                        isCrossProjectSelected = false
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
            if isCrossProjectSelected && crossProjectWorktree == nil {
                isCrossProjectSelected = false
            }

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
                let repositories = visibleRepositories(in: workspace)
                selectedRepository = repositories.first(where: { $0.id == uuid })
            }

            // Restore selected worktree from repository-specific storage first.
            if selectedWorktree == nil, let repository = selectedRepository {
                let worktrees = (repository.worktrees as? Set<Worktree>) ?? []
                if let restoredWorktreeId = getStoredWorktreeId(for: repository) {
                    selectedWorktree = worktrees.first(where: { $0.id == restoredWorktreeId && !$0.isDeleted })
                }

                // Fallback to global selection if repository-specific value is missing.
                if selectedWorktree == nil,
                   let worktreeId = selectedWorktreeId,
                   let uuid = UUID(uuidString: worktreeId) {
                    selectedWorktree = worktrees.first(where: { $0.id == uuid && !$0.isDeleted })
                }

                if selectedWorktree == nil {
                    let candidates = worktrees.filter { !$0.isDeleted }
                    selectedWorktree = candidates.first(where: { $0.isPrimary }) ?? candidates.first
                }
            }

            if !hasShownOnboarding {
                showingOnboarding = true
                hasShownOnboarding = true
            }
        }
        .onChange(of: selectedWorkspace) { _, newValue in
            selectedWorkspaceId = newValue?.id?.uuidString

            if isCrossProjectSelected {
                isCrossProjectSelected = false
                selectedRepository = nil
                selectedWorktree = nil
            }

            // Restore last selected repository for this workspace
            if let workspace = newValue {
                let repositories = visibleRepositories(in: workspace)
                if let lastRepoId = workspace.lastSelectedRepositoryId,
                   let lastRepo = repositories.first(where: { $0.id == lastRepoId }) {
                    selectedRepository = lastRepo
                } else {
                    // Fall back to first repository if last selected does not exist
                    selectedRepository = repositories.first
                }
            } else {
                selectedRepository = nil
            }
        }
        .onChange(of: selectedRepository) { _, newValue in
            selectedRepositoryId = newValue?.id?.uuidString

            if let repo = newValue, isCrossProjectRepository(repo) {
                selectedRepository = nil
                isCrossProjectSelected = true
                prepareCrossProjectWorkspaceIfNeeded()
                return
            }

            if let repo = newValue, repo.isDeleted || repo.isFault {
                selectedRepository = nil
                selectedWorktree = nil
            } else if let repo = newValue {
                isCrossProjectSelected = false

                // Save last selected repository to workspace (debounced to avoid blocking)
                if let workspace = selectedWorkspace {
                    workspace.lastSelectedRepositoryId = repo.id
                    saveTask?.cancel()
                    saveTask = Task {
                        try? await Task.sleep(for: .milliseconds(500))
                        guard !Task.isCancelled else { return }
                        try? viewContext.save()
                    }
                }

                // Restore previously selected worktree for this repository.
                let worktrees = (repo.worktrees as? Set<Worktree>) ?? []
                if let restoredWorktreeId = getStoredWorktreeId(for: repo),
                   let restoredWorktree = worktrees.first(where: { $0.id == restoredWorktreeId && !$0.isDeleted }) {
                    selectedWorktree = restoredWorktree
                } else {
                    let candidates = worktrees.filter { !$0.isDeleted }
                    selectedWorktree = candidates.first(where: { $0.isPrimary }) ?? candidates.first
                }
            }
        }
        .onChange(of: selectedWorktree) { _, newValue in
            selectedWorktreeId = newValue?.id?.uuidString

            if let newWorktree = newValue, !newWorktree.isDeleted {
                previousWorktree = newWorktree
                if let repository = selectedRepository {
                    storeWorktreeSelection(newWorktree.id, for: repository)
                }
                // Update worktree access asynchronously to avoid blocking UI
                Task { @MainActor in
                    try? repositoryManager.updateWorktreeAccess(newWorktree)
                }
            } else if newValue?.isDeleted == true {
                // Worktree was deleted, fall back to primary worktree
                selectedWorktree = nil
                if let repository = selectedRepository {
                    let worktrees = (repository.worktrees as? Set<Worktree>) ?? []
                    selectedWorktree = worktrees.first(where: { $0.isPrimary && !$0.isDeleted })
                }
            }
        }
        .onChange(of: isCrossProjectSelected) { _, newValue in
            if newValue {
                if zenModeBeforeCrossProjectSelection == nil {
                    zenModeBeforeCrossProjectSelection = zenModeEnabled
                }
                zenModeEnabled = true
                selectedRepository = nil
                selectedWorktree = nil
                prepareCrossProjectWorkspaceIfNeeded()
            } else {
                if let previousZenMode = zenModeBeforeCrossProjectSelection {
                    zenModeEnabled = previousZenMode
                    zenModeBeforeCrossProjectSelection = nil
                }
                crossProjectWorktree = nil
            }
        }
        .onChange(of: zenModeEnabled) { _, newValue in
            if isCrossProjectSelected && !newValue {
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
            navigateToChatSession(chatSessionId: chatSessionId)
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
            crossProjectWorktree = nil
            return
        }

        do {
            crossProjectWorktree = try ensureCrossProjectWorktree(for: workspace)
        } catch {
            crossProjectWorktree = nil
        }
    }

    private func navigateToChatSession(chatSessionId: UUID) {
        // Lookup chat session and navigate to its worktree
        let request: NSFetchRequest<ChatSession> = ChatSession.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", chatSessionId as CVarArg)
        request.fetchLimit = 1

        guard let chatSession = try? viewContext.fetch(request).first,
              let worktree = chatSession.worktree,
              let worktreeId = worktree.id,
              let repository = worktree.repository,
              let repoId = repository.id,
              let workspace = repository.workspace,
              let workspaceId = workspace.id else {
            return
        }

        navigateToWorktree(workspaceId: workspaceId, repoId: repoId, worktreeId: worktreeId)

        // Post notification to switch to chat tab with the specific session
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(
                name: .switchToChatSession,
                object: nil,
                userInfo: ["chatSessionId": chatSessionId]
            )
        }
    }

    private func showCommandPalette() {
        // Toggle behavior: close if already visible
        if let existing = commandPaletteController, existing.window?.isVisible == true {
            existing.closeWindow()
            commandPaletteController = nil
            return
        }

        let currentRepositoryId = selectedRepository?.id?.uuidString
            ?? selectedWorktree?.repository?.id?.uuidString

        let controller = CommandPaletteWindowController(
            managedObjectContext: viewContext,
            currentRepositoryId: currentRepositoryId,
            onNavigate: { workspaceId, repoId, worktreeId in
                navigateToWorktree(workspaceId: workspaceId, repoId: repoId, worktreeId: worktreeId)
            }
        )
        commandPaletteController = controller
        controller.showWindow(nil)
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

    private func quickSwitchToPreviousWorktree() {
        let request: NSFetchRequest<Worktree> = Worktree.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Worktree.lastAccessed, ascending: false)]

        guard let worktrees = try? viewContext.fetch(request) else { return }

        // Find first worktree that isn't the current one
        let currentId = selectedWorktree?.id
        guard let target = worktrees.first(where: { $0.id != currentId }),
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

        selectedWorkspace = workspace

        let allRepositories = (workspace.repositories as? Set<Repository>) ?? []
        if let crossProjectRepository = allRepositories.first(where: { $0.id == repoId && isCrossProjectRepository($0) }) {
            isCrossProjectSelected = true
            selectedRepository = nil
            selectedWorktree = nil

            let worktrees = (crossProjectRepository.worktrees as? Set<Worktree>) ?? []
            if let worktree = worktrees.first(where: { $0.id == worktreeId && !$0.isDeleted }) {
                crossProjectWorktree = worktree
            } else {
                prepareCrossProjectWorkspaceIfNeeded()
            }
            return
        }

        isCrossProjectSelected = false
        let repositories = visibleRepositories(in: workspace)
        if let repository = repositories.first(where: { $0.id == repoId }) {
            selectedRepository = repository
            let worktrees = (repository.worktrees as? Set<Worktree>) ?? []
            if let worktree = worktrees.first(where: { $0.id == worktreeId }) {
                selectedWorktree = worktree
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
    RootView(context: PersistenceController.preview.container.viewContext)
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
