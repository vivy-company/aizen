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
    @Binding var showingGitChanges: Bool
    var onWorktreeDeleted: ((Worktree?) -> Void)?

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen", category: "WorktreeDetailView")

    @StateObject private var viewModel: WorktreeViewModel
    @ObservedObject var tabStateManager: WorktreeTabStateManager

    @AppStorage("showChatTab") private var showChatTab = true
    @AppStorage("showTerminalTab") private var showTerminalTab = true
    @AppStorage("showFilesTab") private var showFilesTab = true
    @AppStorage("showBrowserTab") private var showBrowserTab = true
    @AppStorage("showOpenInApp") private var showOpenInApp = true
    @AppStorage("showGitStatus") private var showGitStatus = true
    @AppStorage("zenModeEnabled") private var zenModeEnabled = false
    @AppStorage("terminalThemeName") private var terminalThemeName = "Catppuccin Mocha"
    @State private var selectedTab = "chat"
    @State private var lastOpenedApp: DetectedApp?
    @StateObject private var gitRepositoryService: GitRepositoryService
    @State private var gitIndexWatcher: GitIndexWatcher?
    @State private var fileSearchWindowController: FileSearchWindowController?
    @State private var fileToOpenFromSearch: String?

    init(worktree: Worktree, repositoryManager: RepositoryManager, tabStateManager: WorktreeTabStateManager, showingGitChanges: Binding<Bool>, onWorktreeDeleted: ((Worktree?) -> Void)? = nil) {
        self.worktree = worktree
        self.repositoryManager = repositoryManager
        self.tabStateManager = tabStateManager
        _showingGitChanges = showingGitChanges
        self.onWorktreeDeleted = onWorktreeDeleted
        _viewModel = StateObject(wrappedValue: WorktreeViewModel(worktree: worktree, repositoryManager: repositoryManager))
        _gitRepositoryService = StateObject(wrappedValue: GitRepositoryService(worktreePath: worktree.path ?? ""))
    }

    // MARK: - Helper Managers

    private var gitOperations: WorktreeGitOperations {
        WorktreeGitOperations(
            gitRepositoryService: gitRepositoryService,
            repositoryManager: repositoryManager,
            worktree: worktree,
            logger: logger
        )
    }

    private var sessionManager: WorktreeSessionManager {
        WorktreeSessionManager(
            worktree: worktree,
            viewModel: viewModel,
            logger: logger
        )
    }

    var browserSessions: [BrowserSession] {
        let sessions = (worktree.browserSessions as? Set<BrowserSession>) ?? []
        return sessions.sorted { ($0.createdAt ?? Date()) < ($1.createdAt ?? Date()) }
    }

    var hasActiveSessions: Bool {
        (selectedTab == "chat" && !sessionManager.chatSessions.isEmpty) ||
        (selectedTab == "terminal" && !sessionManager.terminalSessions.isEmpty) ||
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

    private func getTerminalBackgroundColor() -> Color? {
        guard let resourcePath = Bundle.main.resourcePath else { return nil }
        let themesPath = (resourcePath as NSString).appendingPathComponent("ghostty/themes")
        let themeFile = (themesPath as NSString).appendingPathComponent(terminalThemeName)

        guard let content = try? String(contentsOfFile: themeFile, encoding: .utf8) else {
            return nil
        }

        for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("background") {
                let parts = trimmed.split(separator: "=", maxSplits: 1)
                if parts.count == 2 {
                    let colorHex = parts[1].trimmingCharacters(in: .whitespaces)
                    if let color = Color(hex: colorHex) {
                        return color
                    }
                }
            }
        }

        return nil
    }

    @ViewBuilder
    var contentView: some View {
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
                FileTabView(
                    worktree: worktree,
                    fileToOpenFromSearch: $fileToOpenFromSearch
                )
            } else if selectedTab == "browser" {
                BrowserTabView(
                    worktree: worktree,
                    selectedSessionId: $viewModel.selectedBrowserSessionId
                )
            }
        }
    }

    @ToolbarContentBuilder
    var tabPickerToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            Picker(String(localized: "worktree.session.tab"), selection: $selectedTab) {
                if showChatTab {
                    Label(String(localized: "worktree.session.chat"), systemImage: "message").tag("chat")
                }
                if showTerminalTab {
                    Label(String(localized: "worktree.session.terminal"), systemImage: "terminal").tag("terminal")
                }
                if showFilesTab {
                    Label(String(localized: "worktree.session.files"), systemImage: "folder").tag("files")
                }
                if showBrowserTab {
                    Label(String(localized: "worktree.session.browser"), systemImage: "globe").tag("browser")
                }
            }
            .pickerStyle(.segmented)
            .animation(.easeInOut(duration: 0.2), value: selectedTab)
        }
    }

    @ToolbarContentBuilder
    var sessionToolbarItems: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            SessionTabsScrollView(
                selectedTab: selectedTab,
                chatSessions: sessionManager.chatSessions,
                terminalSessions: sessionManager.terminalSessions,
                selectedChatSessionId: $viewModel.selectedChatSessionId,
                selectedTerminalSessionId: $viewModel.selectedTerminalSessionId,
                onCloseChatSession: sessionManager.closeChatSession,
                onCloseTerminalSession: sessionManager.closeTerminalSession,
                onCreateChatSession: sessionManager.createNewChatSession,
                onCreateTerminalSession: sessionManager.createNewTerminalSession
            )
        }
    }

    @ToolbarContentBuilder
    var leadingToolbarItems: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            HStack(spacing: 12) {
                zenModeButton
            }
        }
    }
    
    @ViewBuilder
    private var zenModeButton: some View {
        let button = Button(action: {
            withAnimation(.easeInOut(duration: 0.25)) {
                zenModeEnabled.toggle()
            }
        }) {
            Label("Zen Mode", systemImage: zenModeEnabled ? "pip.enter" : "pip.exit")
        }
        .labelStyle(.iconOnly)
        .help(zenModeEnabled ? "Show Worktree List" : "Hide Worktree List (Zen Mode)")
        
        if #available(macOS 14.0, *) {
            button.symbolEffect(.bounce, value: zenModeEnabled)
        } else {
            button
        }
    }

    @ToolbarContentBuilder
    var trailingToolbarItems: some ToolbarContent {
        if showOpenInApp {
            ToolbarItem {
                OpenInAppButton(
                    lastOpenedApp: lastOpenedApp,
                    appDetector: appDetector,
                    onOpenInLastApp: openInLastApp,
                    onOpenInDetectedApp: openInDetectedApp
                )
            }
        }

        if #available(macOS 26.0, *) {
            ToolbarSpacer(.fixed)
        } else {
            ToolbarItem(placement: .automatic) {
                Spacer().frame(width: 16).fixedSize()
            }
        }

        if showGitStatus {
            ToolbarItem(placement: .automatic) {
                if hasGitChanges {
                    gitStatusView
                }
            }
        }

        ToolbarItem(placement: .automatic) {
            gitSidebarButton
        }
    }
    
    @ViewBuilder
    private var gitStatusView: some View {
        let view = GitStatusView(
            additions: gitRepositoryService.currentStatus.additions,
            deletions: gitRepositoryService.currentStatus.deletions,
            untrackedFiles: gitRepositoryService.currentStatus.untrackedFiles.count
        )
        
        if #available(macOS 14.0, *) {
            view.symbolEffect(.pulse, options: .repeating, value: hasGitChanges)
        } else {
            view
        }
    }
    
    @ViewBuilder
    private var gitSidebarButton: some View {
        let button = Button(action: {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                showingGitChanges.toggle()
            }
        }) {
            Label("Git Changes", systemImage: "sidebar.right")
        }
        .labelStyle(.iconOnly)
        .help("Show Git Changes")

        if #available(macOS 14.0, *) {
            button.symbolEffect(.bounce, value: showingGitChanges)
        } else {
            button
        }
    }

    private func validateSelectedTab() {
        var available: [String] = []
        if showChatTab { available.append("chat") }
        if showTerminalTab { available.append("terminal") }
        if showFilesTab { available.append("files") }
        if showBrowserTab { available.append("browser") }
        if !available.contains(selectedTab) {
            selectedTab = available.first ?? "files"
        }
    }

    private func openFile(_ filePath: String) {
        // Remember the file path so the files tab can open it
        fileToOpenFromSearch = filePath

        // Switch to files tab
        selectedTab = "files"
    }

    private func showFileSearch() {
        guard let worktreePath = worktree.path else { return }

        let windowController = FileSearchWindowController(
            worktreePath: worktreePath,
            onFileSelected: { filePath in
                self.openFile(filePath)
            }
        )

        fileSearchWindowController = windowController
        windowController.showWindow(nil)
    }

    @ViewBuilder
    private var mainContentWithSidebars: some View {
        contentView
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(selectedTab == "terminal" ? getTerminalBackgroundColor() : nil)
            .onReceive(NotificationCenter.default.publisher(for: .fileSearchShortcut)) { _ in
                showFileSearch()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openFileInEditor)) { notification in
                if let path = notification.userInfo?["path"] as? String {
                    openFile(path)
                }
            }
    }

    var body: some View {
        NavigationStack {
            navigationContent
        }
    }

    @ViewBuilder
    private var contentWithBasicModifiers: some View {
        mainContentWithSidebars
            .navigationTitle(worktree.branch ?? String(localized: "worktree.session.worktree"))
            .toolbarBackground(.visible, for: .windowToolbar)
            .toast()
            .onAppear {
                validateSelectedTab()
            }
            .toolbar {
                leadingToolbarItems
                
                tabPickerToolbarItem

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

                trailingToolbarItems
            }
            .task(id: worktree.id) {
                await setupGitMonitoring()
                loadTabState()
                validateSelectedTab()
            }
    }

    @ViewBuilder
    private var navigationContent: some View {
        contentWithBasicModifiers
            .onChange(of: selectedTab) { _ in
                saveTabState()
            }
            .onChange(of: viewModel.selectedChatSessionId) { newValue in
                guard let worktreeId = worktree.id else { return }
                tabStateManager.saveSessionId(newValue, for: "chat", worktreeId: worktreeId)
            }
            .onChange(of: viewModel.selectedTerminalSessionId) { newValue in
                guard let worktreeId = worktree.id else { return }
                tabStateManager.saveSessionId(newValue, for: "terminal", worktreeId: worktreeId)
            }
            .onChange(of: viewModel.selectedBrowserSessionId) { newValue in
                guard let worktreeId = worktree.id else { return }
                tabStateManager.saveSessionId(newValue, for: "browser", worktreeId: worktreeId)
            }
            .onChange(of: viewModel.selectedFileSessionId) { newValue in
                guard let worktreeId = worktree.id else { return }
                tabStateManager.saveSessionId(newValue, for: "files", worktreeId: worktreeId)
            }
            .onDisappear {
                gitIndexWatcher?.stopWatching()
            }
    }

    private func loadTabState() {
        guard let worktreeId = worktree.id else { return }
        let state = tabStateManager.getState(for: worktreeId)
        selectedTab = state.viewType
    }

    private func saveTabState() {
        guard let worktreeId = worktree.id else { return }
        tabStateManager.saveViewType(selectedTab, for: worktreeId)
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


    // MARK: - App Actions

    private func openInLastApp() {
        guard let app = lastOpenedApp else {
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
}

#Preview {
    WorktreeDetailView(
        worktree: Worktree(),
        repositoryManager: RepositoryManager(viewContext: PersistenceController.preview.container.viewContext),
        tabStateManager: WorktreeTabStateManager(),
        showingGitChanges: .constant(false)
    )
}
