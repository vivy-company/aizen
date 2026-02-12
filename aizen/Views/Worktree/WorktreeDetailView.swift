//
//  WorktreeDetailView.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import ACP
import Combine
import os.log
import SwiftUI

struct WorktreeDetailView: View {
    @ObservedObject var worktree: Worktree
    @ObservedObject var repositoryManager: RepositoryManager
    @ObservedObject var appDetector = AppDetector.shared
    @Binding var gitChangesContext: GitChangesContext?
    var onWorktreeDeleted: ((Worktree?) -> Void)?
    let showZenModeButton: Bool

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen", category: "WorktreeDetailView")

    @StateObject private var viewModel: WorktreeViewModel
    @ObservedObject var tabStateManager: WorktreeTabStateManager

    @AppStorage("showChatTab") private var showChatTab = true
    @AppStorage("showTerminalTab") private var showTerminalTab = true
    @AppStorage("showFilesTab") private var showFilesTab = true
    @AppStorage("showBrowserTab") private var showBrowserTab = true
    @AppStorage("showOpenInApp") private var showOpenInApp = true
    @AppStorage("showGitStatus") private var showGitStatus = true
    @AppStorage("showXcodeBuild") private var showXcodeBuild = true
    @AppStorage("zenModeEnabled") private var zenModeEnabled = false
    @AppStorage("terminalThemeName") private var terminalThemeName = "Aizen Dark"
    @State private var selectedTab = "chat"
    @State private var lastOpenedApp: DetectedApp?
    @StateObject private var gitRepositoryService: GitRepositoryService
    @StateObject private var xcodeBuildManager = XcodeBuildManager()
    @StateObject private var tabConfig = TabConfigurationManager.shared
    @State private var gitIndexWatchToken: UUID?
    @State private var gitIndexWatchPath: String?
    @State private var fileSearchWindowController: FileSearchWindowController?
    @State private var fileToOpenFromSearch: String?
    @State private var cachedTerminalBackgroundColor: Color?
    @State private var hasLoadedTabState = false

    init(
        worktree: Worktree,
        repositoryManager: RepositoryManager,
        tabStateManager: WorktreeTabStateManager,
        gitChangesContext: Binding<GitChangesContext?>,
        onWorktreeDeleted: ((Worktree?) -> Void)? = nil,
        showZenModeButton: Bool = true
    ) {
        self.worktree = worktree
        self.repositoryManager = repositoryManager
        self.tabStateManager = tabStateManager
        _gitChangesContext = gitChangesContext
        self.onWorktreeDeleted = onWorktreeDeleted
        self.showZenModeButton = showZenModeButton
        _viewModel = StateObject(wrappedValue: WorktreeViewModel(worktree: worktree, repositoryManager: repositoryManager))
        _gitRepositoryService = StateObject(wrappedValue: GitRepositoryService(worktreePath: worktree.path ?? ""))
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

    private var detailSurfaceColor: Color {
        if selectedTab == "terminal", let cachedTerminalBackgroundColor {
            return cachedTerminalBackgroundColor
        }
        return Color(nsColor: .windowBackgroundColor)
    }

    private func getTerminalBackgroundColor() -> Color {
        Color(nsColor: GhosttyThemeParser.loadBackgroundColor(named: terminalThemeName))
    }

    @ViewBuilder
    var contentView: some View {
        Group {
            if selectedTab == "chat" {
                ChatTabView(
                    worktree: worktree,
                    repositoryManager: repositoryManager,
                    selectedSessionId: $viewModel.selectedChatSessionId,
                    selectedTerminalSessionId: $viewModel.selectedTerminalSessionId,
                    selectedBrowserSessionId: $viewModel.selectedBrowserSessionId
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
                ForEach(tabConfig.tabOrder) { tab in
                    if isTabVisible(tab.id) {
                        Label(LocalizedStringKey(tab.localizedKey), systemImage: tab.icon)
                            .tag(tab.id)
                    }
                }
            }
            .pickerStyle(.segmented)
            .animation(.easeInOut(duration: 0.2), value: selectedTab)
        }
    }

    private func isTabVisible(_ tabId: String) -> Bool {
        switch tabId {
        case "chat": return showChatTab
        case "terminal": return showTerminalTab
        case "files": return showFilesTab
        case "browser": return showBrowserTab
        default: return false
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
                onCreateTerminalSession: sessionManager.createNewTerminalSession,
                onCreateChatWithAgent: { agentId in
                    sessionManager.createNewChatSession(withAgent: agentId)
                },
                onCreateTerminalWithPreset: { preset in
                    sessionManager.createNewTerminalSession(withPreset: preset)
                }
            )
        }
    }

    @ToolbarContentBuilder
    var leadingToolbarItems: some ToolbarContent {
        if showZenModeButton {
            ToolbarItem(placement: .navigation) {
                HStack(spacing: 12) {
                    zenModeButton
                }
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
        .help(zenModeEnabled ? "Show Environment List" : "Hide Environment List (Zen Mode)")

        if #available(macOS 14.0, *) {
            button.symbolEffect(.bounce, value: zenModeEnabled)
        } else {
            button
        }
    }

    
    @ToolbarContentBuilder
    var trailingToolbarItems: some ToolbarContent {
        // Xcode build button (only if fully loaded and ready)
        if showXcodeBuild, xcodeBuildManager.isReady {
            ToolbarItem {
                XcodeBuildButton(buildManager: xcodeBuildManager, worktree: worktree)
            }

            if #available(macOS 26.0, *) {
                ToolbarSpacer(.fixed)
            } else {
                ToolbarItem(placement: .automatic) {
                    Spacer().frame(width: 12).fixedSize()
                }
            }
        }

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
                Spacer().frame(width: 12).fixedSize()
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
    
    private var showingGitChanges: Bool {
        gitChangesContext != nil
    }

    private var gitStatusIcon: String {
        if gitRepositoryService.repositoryState == .notRepository {
            return "square.and.arrow.up.on.square"
        }
        let status = gitRepositoryService.currentStatus
        if !status.conflictedFiles.isEmpty {
            // Has conflicts - warning state
            return "square.and.arrow.up.trianglebadge.exclamationmark"
        } else if hasGitChanges {
            // Has uncommitted changes
            return "square.and.arrow.up.badge.clock"
        } else {
            // Clean state - all committed
            return "square.and.arrow.up.badge.checkmark"
        }
    }

    private var gitStatusHelp: String {
        if gitRepositoryService.repositoryState == .notRepository {
            return "Git is not initialized for this environment"
        }
        let status = gitRepositoryService.currentStatus
        if !status.conflictedFiles.isEmpty {
            return "Git Changes - \(status.conflictedFiles.count) conflict(s)"
        } else if hasGitChanges {
            return "Git Changes - uncommitted changes"
        } else {
            return "Git Changes - clean"
        }
    }

    private var gitStatusColor: Color {
        if gitRepositoryService.repositoryState == .notRepository {
            return .secondary
        }
        let status = gitRepositoryService.currentStatus
        if !status.conflictedFiles.isEmpty {
            return .red
        } else if hasGitChanges {
            return .orange
        } else {
            return .green
        }
    }

    @ViewBuilder
    private var gitSidebarButton: some View {
        let button = Button(action: {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                if gitChangesContext == nil {
                    gitChangesContext = GitChangesContext(worktree: worktree, service: gitRepositoryService)
                } else {
                    gitChangesContext = nil
                }
            }
        }) {
            Label("Git Changes", systemImage: gitStatusIcon)
                .symbolRenderingMode(.palette)
                .foregroundStyle(gitStatusColor, .primary, .clear)
        }
        .labelStyle(.iconOnly)
        .help(gitStatusHelp)

        if #available(macOS 14.0, *) {
            button.symbolEffect(.bounce, value: showingGitChanges)
        } else {
            button
        }
    }

    private func validateSelectedTab() {
        let visibleTabs = tabConfig.tabOrder.filter { isTabVisible($0.id) }
        if !visibleTabs.contains(where: { $0.id == selectedTab }) {
            selectedTab = visibleTabs.first?.id ?? "files"
        }
    }

    private func openFile(_ filePath: String) {
        // Remember the file path so the files tab can open it
        fileToOpenFromSearch = filePath

        // Switch to files tab
        selectedTab = "files"
    }

    private func showFileSearch() {
        // Toggle behavior: close if already visible
        if let existing = fileSearchWindowController, existing.window?.isVisible == true {
            existing.closeWindow()
            fileSearchWindowController = nil
            return
        }

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
        ZStack(alignment: .top) {
            contentView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(detailSurfaceColor)

            // Permission banner for pending requests in other sessions
            PermissionBannerView(
                currentChatSessionId: viewModel.selectedChatSessionId,
                onNavigate: { sessionId in
                    navigateToChatSession(sessionId)
                }
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .fileSearchShortcut)) { _ in
            showFileSearch()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openFileInEditor)) { notification in
            if let path = notification.userInfo?["path"] as? String {
                openFile(path)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .sendMessageToChat)) { notification in
            handleSendMessageToChat(notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToChat)) { notification in
            handleSwitchToChat(notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToChatSession)) { notification in
            handleSwitchToChatSession(notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: .resumeChatSession)) { notification in
            guard let userInfo = notification.userInfo,
                  let chatSessionId = userInfo["chatSessionId"] as? UUID,
                  let worktreeId = userInfo["worktreeId"] as? UUID,
                  worktreeId == worktree.id else {
                return
            }
            navigateToChatSession(chatSessionId)
        }
    }

    private func navigateToChatSession(_ sessionId: UUID) {
        guard let worktreeId = worktree.id else { return }
        // Fetch session directly to check if it belongs to this worktree
        // (avoids stale relationship cache after reattachment)
        let request: NSFetchRequest<ChatSession> = ChatSession.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@ AND worktree.id == %@", sessionId as CVarArg, worktreeId as CVarArg)
        request.fetchLimit = 1

        if let _ = try? worktree.managedObjectContext?.fetch(request).first {
            selectedTab = "chat"
            viewModel.selectedChatSessionId = sessionId
        } else {
            NotificationCenter.default.post(
                name: .navigateToChatSession,
                object: nil,
                userInfo: ["chatSessionId": sessionId]
            )
        }
    }

    private func handleSwitchToChatSession(_ notification: Notification) {
        guard let sessionId = notification.userInfo?["chatSessionId"] as? UUID else {
            return
        }
        guard let worktreeId = worktree.id else { return }
        // Fetch session directly to verify it belongs to this worktree
        // (avoids stale relationship cache after reattachment)
        let request: NSFetchRequest<ChatSession> = ChatSession.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@ AND worktree.id == %@", sessionId as CVarArg, worktreeId as CVarArg)
        request.fetchLimit = 1

        if let _ = try? worktree.managedObjectContext?.fetch(request).first {
            selectedTab = "chat"
            viewModel.selectedChatSessionId = sessionId
        }
    }

    private func handleSendMessageToChat(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let sessionId = userInfo["sessionId"] as? UUID else {
            return
        }

        // Get attachment from notification (new way) or create from message (legacy way)
        let attachment: ChatAttachment
        if let existingAttachment = userInfo["attachment"] as? ChatAttachment {
            attachment = existingAttachment
        } else if let message = userInfo["message"] as? String {
            attachment = .reviewComments(message)
        } else {
            return
        }

        // Store attachment (user can add context before sending)
        ChatSessionManager.shared.setPendingAttachments([attachment], for: sessionId)

        if doesChatSessionBelongToCurrentWorktree(sessionId) {
            selectedTab = "chat"
            viewModel.selectedChatSessionId = sessionId
        } else {
            NotificationCenter.default.post(
                name: .navigateToChatSession,
                object: nil,
                userInfo: ["chatSessionId": sessionId]
            )
        }
    }

    private func handleSwitchToChat(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let sessionId = userInfo["sessionId"] as? UUID else {
            return
        }

        if doesChatSessionBelongToCurrentWorktree(sessionId) {
            selectedTab = "chat"
            viewModel.selectedChatSessionId = sessionId
        } else {
            NotificationCenter.default.post(
                name: .navigateToChatSession,
                object: nil,
                userInfo: ["chatSessionId": sessionId]
            )
        }
    }

    private func doesChatSessionBelongToCurrentWorktree(_ sessionId: UUID) -> Bool {
        guard let worktreeId = worktree.id else { return false }
        let request: NSFetchRequest<ChatSession> = ChatSession.fetchRequest()
        request.predicate = NSPredicate(
            format: "id == %@ AND worktree.id == %@",
            sessionId as CVarArg,
            worktreeId as CVarArg
        )
        request.fetchLimit = 1
        return ((try? worktree.managedObjectContext?.fetch(request).first) != nil)
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
            .background(detailSurfaceColor.ignoresSafeArea(.container, edges: .top))
            .toolbarBackground(.visible, for: .windowToolbar)
            .toast()
            .onAppear {
                cachedTerminalBackgroundColor = getTerminalBackgroundColor()
            }
            .onChange(of: terminalThemeName) { _, _ in
                cachedTerminalBackgroundColor = getTerminalBackgroundColor()
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
                        Spacer()
                    }
                }

                trailingToolbarItems
            }
            .task(id: worktree.id) {
                hasLoadedTabState = false
                loadTabState()
                validateSelectedTab()
                hasLoadedTabState = true
                await setupGitMonitoring()
                xcodeBuildManager.detectProject(at: worktree.path ?? "")
            }
    }

    @ViewBuilder
    private var navigationContent: some View {
        contentWithBasicModifiers
            .onChange(of: selectedTab) { _, _ in
                guard hasLoadedTabState else { return }
                saveTabState()
            }
            .onChange(of: viewModel.selectedChatSessionId) { _, newValue in
                guard let worktreeId = worktree.id else { return }
                tabStateManager.saveSessionId(newValue, for: "chat", worktreeId: worktreeId)
            }
            .onChange(of: viewModel.selectedTerminalSessionId) { _, newValue in
                guard let worktreeId = worktree.id else { return }
                tabStateManager.saveSessionId(newValue, for: "terminal", worktreeId: worktreeId)
            }
            .onChange(of: viewModel.selectedBrowserSessionId) { _, newValue in
                guard let worktreeId = worktree.id else { return }
                tabStateManager.saveSessionId(newValue, for: "browser", worktreeId: worktreeId)
            }
            .onChange(of: viewModel.selectedFileSessionId) { _, newValue in
                guard let worktreeId = worktree.id else { return }
                tabStateManager.saveSessionId(newValue, for: "files", worktreeId: worktreeId)
            }
            .onDisappear {
                if let token = gitIndexWatchToken, let path = gitIndexWatchPath {
                    Task {
                        await GitIndexWatchCenter.shared.removeSubscriber(worktreePath: path, id: token)
                    }
                }
                gitIndexWatchToken = nil
                gitIndexWatchPath = nil
            }
    }

    private func loadTabState() {
        guard let worktreeId = worktree.id else { return }

        if tabStateManager.hasStoredState(for: worktreeId) {
            // Restore saved state
            let state = tabStateManager.getState(for: worktreeId)
            selectedTab = state.viewType
            viewModel.selectedChatSessionId = state.chatSessionId
            viewModel.selectedTerminalSessionId = state.terminalSessionId
            viewModel.selectedBrowserSessionId = state.browserSessionId
            viewModel.selectedFileSessionId = state.fileSessionId
        } else {
            // Fresh worktree - use configured default tab
            selectedTab = tabConfig.effectiveDefaultTab(
                showChat: showChatTab,
                showTerminal: showTerminalTab,
                showFiles: showFilesTab,
                showBrowser: showBrowserTab
            )
        }
    }

    private func saveTabState() {
        guard let worktreeId = worktree.id else { return }
        tabStateManager.saveViewType(selectedTab, for: worktreeId)
    }

    private func setupGitMonitoring() async {
        guard let worktreePath = worktree.path else { return }

        // Update service path and reload status
        gitRepositoryService.updateWorktreePath(worktreePath)

        // Dedupe polling per worktree path
        if let token = gitIndexWatchToken, let path = gitIndexWatchPath {
            await GitIndexWatchCenter.shared.removeSubscriber(worktreePath: path, id: token)
            gitIndexWatchToken = nil
            gitIndexWatchPath = nil
        }

        let service = gitRepositoryService
        let token = await GitIndexWatchCenter.shared.addSubscriber(worktreePath: worktreePath) { [weak service] in
            service?.reloadStatus(lightweight: true)
        }
        gitIndexWatchToken = token
        gitIndexWatchPath = worktreePath
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
        gitChangesContext: .constant(nil)
    )
}
