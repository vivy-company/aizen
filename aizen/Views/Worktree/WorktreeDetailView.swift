//
//  WorktreeDetailView.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import SwiftUI
import os.log
import Combine

struct WorktreeDetailView: View {
    @ObservedObject var worktree: Worktree
    @ObservedObject var repositoryManager: RepositoryManager
    @ObservedObject var appDetector = AppDetector.shared
    var onWorktreeDeleted: ((Worktree?) -> Void)?

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen", category: "WorktreeDetailView")

    @StateObject private var viewModel: WorktreeViewModel

    @AppStorage("worktreeTabStates") private var worktreeTabStatesData: String = "{}"
    @State private var selectedTab = "chat"
    @State private var lastOpenedApp: DetectedApp?
    @State private var showingGitSidebar = false
    @State private var sidebarWidth: CGFloat = 350
    @StateObject private var gitRepositoryService: GitRepositoryService
    @State private var gitIndexWatcher: GitIndexWatcher?
    @State private var gitOperationHandler: GitOperationHandler?

    init(worktree: Worktree, repositoryManager: RepositoryManager, onWorktreeDeleted: ((Worktree?) -> Void)? = nil) {
        self.worktree = worktree
        self.repositoryManager = repositoryManager
        self.onWorktreeDeleted = onWorktreeDeleted
        _viewModel = StateObject(wrappedValue: WorktreeViewModel(worktree: worktree, repositoryManager: repositoryManager))
        _gitRepositoryService = StateObject(wrappedValue: GitRepositoryService(worktreePath: worktree.path ?? ""))
    }

    private func ensureGitHandler() -> GitOperationHandler {
        if let handler = gitOperationHandler {
            return handler
        }
        let handler = GitOperationHandler(
            gitService: gitRepositoryService,
            repositoryManager: repositoryManager,
            logger: logger
        )
        gitOperationHandler = handler
        return handler
    }

    // MARK: - Tab State Persistence

    private func loadTabState() {
        guard let worktreeId = worktree.id?.uuidString else { return }

        if let data = worktreeTabStatesData.data(using: .utf8),
           let tabStates = try? JSONDecoder().decode([String: String].self, from: data),
           let savedTab = tabStates[worktreeId] {
            selectedTab = savedTab
        } else {
            selectedTab = "chat"
        }
    }

    private func saveTabState() {
        guard let worktreeId = worktree.id?.uuidString else { return }

        var tabStates: [String: String] = [:]
        if let data = worktreeTabStatesData.data(using: .utf8),
           let existing = try? JSONDecoder().decode([String: String].self, from: data) {
            tabStates = existing
        }

        tabStates[worktreeId] = selectedTab

        if let encoded = try? JSONEncoder().encode(tabStates),
           let jsonString = String(data: encoded, encoding: .utf8) {
            worktreeTabStatesData = jsonString
        }
    }

    var chatSessions: [ChatSession] {
        let sessions = (worktree.chatSessions as? Set<ChatSession>) ?? []
        return sessions.sorted { ($0.createdAt ?? Date()) < ($1.createdAt ?? Date()) }
    }

    var terminalSessions: [TerminalSession] {
        let sessions = (worktree.terminalSessions as? Set<TerminalSession>) ?? []
        return sessions.sorted { ($0.createdAt ?? Date()) < ($1.createdAt ?? Date()) }
    }

    var browserSessions: [BrowserSession] {
        let sessions = (worktree.browserSessions as? Set<BrowserSession>) ?? []
        return sessions.sorted { ($0.createdAt ?? Date()) < ($1.createdAt ?? Date()) }
    }

    var hasActiveSessions: Bool {
        (selectedTab == "chat" && !chatSessions.isEmpty) ||
        (selectedTab == "terminal" && !terminalSessions.isEmpty) ||
        (selectedTab == "browser" && !browserSessions.isEmpty)
    }

    var shouldShowSessionToolbar: Bool {
        selectedTab != "files" && selectedTab != "browser" && hasActiveSessions
    }

    var hasGitChanges: Bool {
        gitRepositoryService.currentStatus.additions > 0 ||
        gitRepositoryService.currentStatus.deletions > 0 ||
        gitRepositoryService.currentStatus.untrackedFiles.count > 0
    }



    @ViewBuilder
    var contentView: some View {
        // Show diff view if file is selected, otherwise show normal content
        if let selectedFile = viewModel.selectedDiffFile,
           let worktreePath = worktree.path {
            DiffView(
                fileName: (selectedFile as NSString).lastPathComponent,
                filePath: selectedFile,
                repoPath: worktreePath,
                onClose: {
                    viewModel.closeDiffView()
                }
            )
            .transition(.opacity)
        } else {
            Group {
                if selectedTab == "chat" {
                    ChatTabView(
                        worktree: worktree,
                        selectedSessionId: $viewModel.selectedChatSessionId
                    )
                } else if selectedTab == "terminal" {
                    TerminalTabView(
                        worktree: worktree,
                        selectedSessionId: $viewModel.selectedTerminalSessionId,
                        repositoryManager: repositoryManager
                    )
                } else if selectedTab == "files" {
                    FileTabView(worktree: worktree)
                } else if selectedTab == "browser" {
                    BrowserTabView(
                        worktree: worktree,
                        selectedSessionId: $viewModel.selectedBrowserSessionId
                    )
                }
            }
        }
    }

    @ToolbarContentBuilder
    var sessionToolbarItems: some ToolbarContent {

        ToolbarItem(placement: .automatic) {
            SessionTabsScrollView(
                selectedTab: selectedTab,
                chatSessions: chatSessions,
                terminalSessions: terminalSessions,
                selectedChatSessionId: $viewModel.selectedChatSessionId,
                selectedTerminalSessionId: $viewModel.selectedTerminalSessionId,
                onCloseChatSession: closeChatSession,
                onCloseTerminalSession: closeTerminalSession
            )
        }
        
        if #available(macOS 26.0, *) {
            ToolbarSpacer(.fixed)
        } else {
            ToolbarItem(placement: .automatic) {
                Spacer().frame(width: 16).fixedSize()
            }
        }

        ToolbarItem(placement: .automatic) {
            if selectedTab == "chat" {
                Button {
                    createNewChatSession()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11))
                }
                .help(String(localized: "worktree.session.newChat"))
            } else {
                Button {
                    createNewTerminalSession()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11))
                }
                .help(String(localized: "worktree.session.newTerminal"))
            }
        }

    }

    @ToolbarContentBuilder
    var appAndGitToolbarItems: some ToolbarContent {
        ToolbarItem {
            OpenInAppButton(
                lastOpenedApp: lastOpenedApp,
                appDetector: appDetector,
                onOpenInLastApp: openInLastApp,
                onOpenInDetectedApp: openInDetectedApp
            )
        }

        if #available(macOS 26.0, *) {
            ToolbarSpacer(.fixed)
        } else {
            ToolbarItem(placement: .automatic) {
                Spacer().frame(width: 16).fixedSize()
            }
        }

        ToolbarItem(placement: .automatic) {
            if hasGitChanges {
                GitStatusView(
                    additions: gitRepositoryService.currentStatus.additions,
                    deletions: gitRepositoryService.currentStatus.deletions,
                    untrackedFiles: gitRepositoryService.currentStatus.untrackedFiles.count
                )
            }
        }

        ToolbarItem(placement: .automatic) {
            Button(action: {
                showingGitSidebar.toggle()
            }) {
                Label("Git Changes", systemImage: "sidebar.right")
            }
            .labelStyle(.iconOnly)
            .help("Show Git Changes")
        }
    }

    var body: some View {
        NavigationStack {
            contentView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .safeAreaInset(edge: .trailing, spacing: 0) {
                    if showingGitSidebar {
                        GitSidebarView(
                            worktreePath: worktree.path ?? "",
                            repository: worktree.repository!,
                            repositoryManager: repositoryManager,
                            onClose: { showingGitSidebar = false },
                            gitStatus: gitRepositoryService.currentStatus,
                            isOperationPending: gitRepositoryService.isOperationPending,
                            selectedDiffFile: viewModel.selectedDiffFile,
                            onStageFile: stageFile,
                            onUnstageFile: unstageFile,
                            onStageAll: stageAllFiles,
                            onUnstageAll: unstageAllFiles,
                            onCommit: commitChanges,
                            onAmendCommit: amendCommit,
                            onCommitWithSignoff: commitWithSignoff,
                            onSwitchBranch: switchBranch,
                            onCreateBranch: createBranch,
                            onFetch: fetchChanges,
                            onPull: pullChanges,
                            onPush: pushChanges,
                            onFileClick: { file in
                                viewModel.selectFileForDiff(file)
                            }
                        )
                        .frame(width: sidebarWidth)
                        .id(gitRepositoryService.currentStatus.id)
                        .transition(.move(edge: .trailing))
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: showingGitSidebar)
                .animation(.easeInOut(duration: 0.2), value: viewModel.selectedDiffFile)
            .navigationTitle(worktree.branch ?? String(localized: "worktree.session.worktree"))
            .toolbarBackground(.visible, for: .windowToolbar)
            .toast()
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Picker(String(localized: "worktree.session.tab"), selection: $selectedTab) {
                        Label(String(localized: "worktree.session.chat"), systemImage: "message").tag("chat")
                        Label(String(localized: "worktree.session.terminal"), systemImage: "terminal").tag("terminal")
                        Label(String(localized: "worktree.session.files"), systemImage: "folder").tag("files")
                        Label(String(localized: "worktree.session.browser"), systemImage: "globe").tag("browser")
                    }
                    .pickerStyle(.segmented)
                }


                if shouldShowSessionToolbar {
                    sessionToolbarItems
                }

                if #available(macOS 26.0, *) {
                    ToolbarSpacer()
                } else {
                    ToolbarItem(placement: .automatic) {
                        Spacer().frame(width: 16).fixedSize()
                    }
                }

                appAndGitToolbarItems
            }
            .task {
                await setupGitMonitoring()
            }
            .onAppear {
                loadTabState()
            }
            .onChange(of: worktree.id) { newId in
                Task {
                    await setupGitMonitoring()
                }
                loadTabState()
            }
            .onChange(of: selectedTab) { _ in
                saveTabState()
            }
            .onDisappear {
                gitIndexWatcher?.stopWatching()
            }
        }
    }

    private func setupGitMonitoring() async {
        guard let worktreePath = worktree.path else { return }

        // Initial load
        gitRepositoryService.reloadStatus()

        // Setup file system watcher (now a regular class, non-blocking)
        let watcher = GitIndexWatcher(worktreePath: worktreePath)
        watcher.startWatching { [weak gitRepositoryService] in
            gitRepositoryService?.reloadStatus()
        }
        gitIndexWatcher = watcher
    }


    private func closeChatSession(_ session: ChatSession) {
        guard let context = worktree.managedObjectContext else { return }

        if let id = session.id {
            ChatSessionManager.shared.removeAgentSession(for: id)
        }

        if viewModel.selectedChatSessionId == session.id {
            if let index = chatSessions.firstIndex(where: { $0.id == session.id }) {
                if index > 0 {
                    viewModel.selectedChatSessionId = chatSessions[index - 1].id
                } else if chatSessions.count > 1 {
                    viewModel.selectedChatSessionId = chatSessions[index + 1].id
                } else {
                    viewModel.selectedChatSessionId = nil
                }
            }
        }

        context.delete(session)

        do {
            try context.save()
        } catch {
            logger.error("Failed to delete chat session: \(error.localizedDescription)")
        }
    }

    private func closeTerminalSession(_ session: TerminalSession) {
        guard let context = worktree.managedObjectContext else { return }

        if let id = session.id {
            TerminalSessionManager.shared.removeAllTerminals(for: id)
        }

        if viewModel.selectedTerminalSessionId == session.id {
            if let index = terminalSessions.firstIndex(where: { $0.id == session.id }) {
                if index > 0 {
                    viewModel.selectedTerminalSessionId = terminalSessions[index - 1].id
                } else if terminalSessions.count > 1 {
                    viewModel.selectedTerminalSessionId = terminalSessions[index + 1].id
                } else {
                    viewModel.selectedTerminalSessionId = nil
                }
            }
        }

        context.delete(session)

        do {
            try context.save()
        } catch {
            logger.error("Failed to delete terminal session: \(error.localizedDescription)")
        }
    }

    private func openInLastApp() {
        guard let app = lastOpenedApp else {
            // Open in Finder by default
            if let finder = appDetector.getApps(for: .finder).first {
                openInDetectedApp(finder)
            }
            return
        }
        openInDetectedApp(app)
    }

    private func openInDetectedApp(_ app: DetectedApp) {
        guard let path = worktree.path else { return }
        lastOpenedApp = app
        appDetector.openPath(path, with: app)
    }

    private func createNewChatSession() {
        guard let context = worktree.managedObjectContext else { return }

        let session = ChatSession(context: context)
        session.id = UUID()
        let defaultAgent = AgentRouter().defaultAgent
        let displayName = AgentRegistry.shared.getMetadata(for: defaultAgent)?.name ?? defaultAgent.capitalized
        session.title = displayName
        session.agentName = defaultAgent
        session.createdAt = Date()
        session.worktree = worktree

        do {
            try context.save()
            viewModel.selectedChatSessionId = session.id
        } catch {
            logger.error("Failed to create chat session: \(error.localizedDescription)")
        }
    }

    private func createNewTerminalSession() {
        guard let context = worktree.managedObjectContext else { return }

        let terminalSessions = (worktree.terminalSessions as? Set<TerminalSession>) ?? []

        let session = TerminalSession(context: context)
        session.id = UUID()
        session.title = String(localized: "worktree.session.terminalTitle \(terminalSessions.count + 1)")
        session.createdAt = Date()
        session.worktree = worktree

        do {
            try context.save()
            viewModel.selectedTerminalSessionId = session.id
        } catch {
            logger.error("Failed to create terminal session: \(error.localizedDescription)")
        }
    }

    // MARK: - Git Operations

    private func stageFile(_ file: String) {
        ensureGitHandler().stageFile(file)
    }

    private func unstageFile(_ file: String) {
        ensureGitHandler().unstageFile(file)
    }

    private func stageAllFiles(onComplete: @escaping () -> Void) {
        ensureGitHandler().stageAll(onComplete: onComplete)
    }

    private func unstageAllFiles() {
        ensureGitHandler().unstageAll()
    }

    private func commitChanges(_ message: String) {
        ensureGitHandler().commit(message)
    }

    private func amendCommit(_ message: String) {
        ensureGitHandler().amendCommit(message)
    }

    private func commitWithSignoff(_ message: String) {
        ensureGitHandler().commitWithSignoff(message)
    }

    private func switchBranch(_ branch: String) {
        ensureGitHandler().switchBranch(branch, repository: worktree.repository)
    }

    private func createBranch(_ name: String) {
        ensureGitHandler().createBranch(name, repository: worktree.repository)
    }

    private func fetchChanges() {
        ensureGitHandler().fetch(repository: worktree.repository)
    }

    private func pullChanges() {
        ensureGitHandler().pull(repository: worktree.repository)
    }

    private func pushChanges() {
        ensureGitHandler().push(repository: worktree.repository)
    }
}

#Preview {
    WorktreeDetailView(
        worktree: Worktree(),
        repositoryManager: RepositoryManager(viewContext: PersistenceController.preview.container.viewContext)
    )
}
