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
    @ObservedObject var repositoryManager: WorkspaceRepositoryStore
    @ObservedObject var appDetector = AppDetector.shared
    @Binding var gitChangesContext: GitChangesContext?
    var onWorktreeDeleted: ((Worktree?) -> Void)?
    let showZenModeButton: Bool

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen", category: "WorktreeDetailView")

    @StateObject private var viewModel: WorktreeDetailStore
    @ObservedObject var tabStateManager: WorktreeTabStateStore

    @AppStorage("showChatTab") private var showChatTab = true
    @AppStorage("showTerminalTab") private var showTerminalTab = true
    @AppStorage("showFilesTab") private var showFilesTab = true
    @AppStorage("showBrowserTab") private var showBrowserTab = true
    @AppStorage("showOpenInApp") private var showOpenInApp = true
    @AppStorage("showGitStatus") private var showGitStatus = true
    @AppStorage("showXcodeBuild") private var showXcodeBuild = true
    @AppStorage("zenModeEnabled") private var zenModeEnabled = false
    @State private var selectedTab = "chat"
    @State private var lastOpenedApp: DetectedApp?
    private let worktreeRuntime: WorktreeRuntime
    @ObservedObject private var gitSummaryStore: GitSummaryStore
    @ObservedObject private var xcodeBuildManager: XcodeBuildStore
    @StateObject private var tabConfig = TabConfigurationStore.shared
    @State private var fileSearchWindowController: FileSearchWindowController?
    @State private var fileToOpenFromSearch: String?
    @State private var cachedTerminalBackgroundColor: Color?
    @State private var hasLoadedTabState = false
    @Environment(\.colorScheme) private var colorScheme

    init(
        worktree: Worktree,
        repositoryManager: WorkspaceRepositoryStore,
        tabStateManager: WorktreeTabStateStore,
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
        let runtime = WorktreeRuntimeCoordinator.shared.runtime(for: worktree.path ?? "")
        self.worktreeRuntime = runtime
        _viewModel = StateObject(wrappedValue: WorktreeDetailStore(worktree: worktree, repositoryManager: repositoryManager))
        _gitSummaryStore = ObservedObject(wrappedValue: runtime.summaryStore)
        _xcodeBuildManager = ObservedObject(wrappedValue: runtime.xcodeBuildManager)
    }

    private var sessionManager: WorktreeSessionCoordinator {
        WorktreeSessionCoordinator(
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
        gitSummaryStore.status.additions > 0 ||
        gitSummaryStore.status.deletions > 0 ||
        gitSummaryStore.status.untrackedFiles.count > 0
    }

    private var detailSurfaceColor: Color {
        if selectedTab == "terminal", let cachedTerminalBackgroundColor {
            return cachedTerminalBackgroundColor
        }
        return AppSurfaceTheme.backgroundColor(colorScheme: colorScheme)
    }

    private func getTerminalBackgroundColor() -> Color {
        AppSurfaceTheme.backgroundColor(colorScheme: colorScheme)
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
                AizenTerminalRootContainer {
                    TerminalTabView(
                        worktree: worktree,
                        selectedSessionId: $viewModel.selectedTerminalSessionId,
                        repositoryManager: repositoryManager
                    )
                }
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

    private var visibleTabIds: [String] {
        tabConfig.tabOrder
            .map(\.id)
            .filter { isTabVisible($0) }
    }

    private func selectVisibleTab(at oneBasedIndex: Int) {
        let zeroBased = oneBasedIndex - 1
        guard zeroBased >= 0, zeroBased < visibleTabIds.count else { return }
        selectedTab = visibleTabIds[zeroBased]
    }

    private func cycleVisibleTab(step: Int) {
        guard !visibleTabIds.isEmpty else { return }
        guard let currentIndex = visibleTabIds.firstIndex(of: selectedTab) else {
            selectedTab = visibleTabIds[0]
            return
        }

        let count = visibleTabIds.count
        let nextIndex = (currentIndex + step + count) % count
        selectedTab = visibleTabIds[nextIndex]
    }

    @ToolbarContentBuilder
    var sessionToolbarItems: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            if shouldShowSessionToolbar {
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
    }

    @ToolbarContentBuilder
    var leadingToolbarItems: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            if showZenModeButton {
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
        ToolbarItem {
            if showXcodeBuild, xcodeBuildManager.isReady {
                XcodeBuildButton(buildManager: xcodeBuildManager, worktree: worktree)
            }
        }

        if #available(macOS 26.0, *) {
            ToolbarSpacer(.fixed)
        } else {
            ToolbarItem(placement: .automatic) {
                Spacer().frame(width: 12).fixedSize()
            }
        }

        ToolbarItem {
            if showOpenInApp {
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

        ToolbarItem(placement: .automatic) {
            if showGitStatus && hasGitChanges {
                gitStatusView
            }
        }

        ToolbarItem(placement: .automatic) {
            gitSidebarButton
        }
    }
    
    @ViewBuilder
    private var gitStatusView: some View {
        GitStatusView(
            additions: gitSummaryStore.status.additions,
            deletions: gitSummaryStore.status.deletions,
            untrackedFiles: gitSummaryStore.status.untrackedFiles.count
        )
    }
    
    private var showingGitChanges: Bool {
        gitChangesContext != nil
    }

    private var gitStatusIcon: String {
        if gitSummaryStore.repositoryState == .notRepository {
            return "square.and.arrow.up.on.square"
        }
        let status = gitSummaryStore.status
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
        if gitSummaryStore.repositoryState == .notRepository {
            return "Git is not initialized for this environment"
        }
        let status = gitSummaryStore.status
        if !status.conflictedFiles.isEmpty {
            return "Git Changes - \(status.conflictedFiles.count) conflict(s)"
        } else if hasGitChanges {
            return "Git Changes - uncommitted changes"
        } else {
            return "Git Changes - clean"
        }
    }

    private var gitStatusColor: Color {
        if gitSummaryStore.repositoryState == .notRepository {
            return .secondary
        }
        let status = gitSummaryStore.status
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
                    gitChangesContext = GitChangesContext(worktree: worktree, runtime: worktreeRuntime)
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
        .onReceive(NotificationCenter.default.publisher(for: .switchToWorktreeTab)) { notification in
            handleSwitchToWorktreeTab(notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToTerminalSession)) { notification in
            handleSwitchToTerminalSession(notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToBrowserSession)) { notification in
            handleSwitchToBrowserSession(notification)
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

    private func handleSwitchToWorktreeTab(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let targetWorktreeId = userInfo["worktreeId"] as? UUID,
              let tabId = userInfo["tabId"] as? String,
              targetWorktreeId == worktree.id else {
            return
        }

        guard visibleTabIds.contains(tabId) else { return }
        selectedTab = tabId
    }

    private func handleSwitchToTerminalSession(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let targetWorktreeId = userInfo["worktreeId"] as? UUID,
              let sessionId = userInfo["sessionId"] as? UUID,
              targetWorktreeId == worktree.id else {
            return
        }

        let request: NSFetchRequest<TerminalSession> = TerminalSession.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@ AND worktree.id == %@", sessionId as CVarArg, targetWorktreeId as CVarArg)
        request.fetchLimit = 1

        if let _ = try? worktree.managedObjectContext?.fetch(request).first {
            selectedTab = "terminal"
            viewModel.selectedTerminalSessionId = sessionId
        }
    }

    private func handleSwitchToBrowserSession(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let targetWorktreeId = userInfo["worktreeId"] as? UUID,
              let sessionId = userInfo["sessionId"] as? UUID,
              targetWorktreeId == worktree.id else {
            return
        }

        let request: NSFetchRequest<BrowserSession> = BrowserSession.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@ AND worktree.id == %@", sessionId as CVarArg, targetWorktreeId as CVarArg)
        request.fetchLimit = 1

        if let _ = try? worktree.managedObjectContext?.fetch(request).first {
            selectedTab = "browser"
            viewModel.selectedBrowserSessionId = sessionId
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
        ChatSessionRegistry.shared.setPendingAttachments([attachment], for: sessionId)

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
            .task(id: colorScheme) {
                cachedTerminalBackgroundColor = getTerminalBackgroundColor()
            }
            .toolbar {
                leadingToolbarItems

                tabPickerToolbarItem

                sessionToolbarItems

                if #available(macOS 26.0, *) {
                    ToolbarSpacer()
                } else {
                    ToolbarItem(placement: .automatic) {
                        Spacer()
                    }
                }

                trailingToolbarItems
            }
            .background {
                Group {
                    Button("") { cycleVisibleTab(step: 1) }
                        .keyboardShortcut(.tab, modifiers: [.control])
                    Button("") { cycleVisibleTab(step: -1) }
                        .keyboardShortcut(.tab, modifiers: [.control, .shift])
                    Button("") { selectVisibleTab(at: 1) }
                        .keyboardShortcut("1", modifiers: .command)
                    Button("") { selectVisibleTab(at: 2) }
                        .keyboardShortcut("2", modifiers: .command)
                    Button("") { selectVisibleTab(at: 3) }
                        .keyboardShortcut("3", modifiers: .command)
                    Button("") { selectVisibleTab(at: 4) }
                        .keyboardShortcut("4", modifiers: .command)
                }
                .hidden()
            }
            .task(id: worktree.id) {
                hasLoadedTabState = false
                loadTabState()
                validateSelectedTab()
                hasLoadedTabState = true
                worktreeRuntime.attachDetail(showXcode: showXcodeBuild)
            }
    }

    @ViewBuilder
    private var navigationContent: some View {
        contentWithBasicModifiers
            .task(id: selectedTab) {
                guard hasLoadedTabState else { return }
                saveTabState()
            }
            .task(id: viewModel.selectedChatSessionId) {
                guard let worktreeId = worktree.id else { return }
                tabStateManager.saveSessionId(viewModel.selectedChatSessionId, for: "chat", worktreeId: worktreeId)
            }
            .task(id: viewModel.selectedTerminalSessionId) {
                guard let worktreeId = worktree.id else { return }
                tabStateManager.saveSessionId(viewModel.selectedTerminalSessionId, for: "terminal", worktreeId: worktreeId)
            }
            .task(id: viewModel.selectedBrowserSessionId) {
                guard let worktreeId = worktree.id else { return }
                tabStateManager.saveSessionId(viewModel.selectedBrowserSessionId, for: "browser", worktreeId: worktreeId)
            }
            .task(id: viewModel.selectedFileSessionId) {
                guard let worktreeId = worktree.id else { return }
                tabStateManager.saveSessionId(viewModel.selectedFileSessionId, for: "files", worktreeId: worktreeId)
            }
            .onDisappear {
                worktreeRuntime.detachDetail()
            }
            .task(id: showXcodeBuild) {
                worktreeRuntime.updateDetailOptions(showXcode: showXcodeBuild)
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
        repositoryManager: WorkspaceRepositoryStore(viewContext: PersistenceController.preview.container.viewContext),
        tabStateManager: WorktreeTabStateStore(),
        gitChangesContext: .constant(nil)
    )
}
