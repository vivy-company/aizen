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

    @StateObject var viewModel: WorktreeDetailStore
    @ObservedObject var tabStateManager: WorktreeTabStateStore

    @AppStorage("showChatTab") var showChatTab = true
    @AppStorage("showTerminalTab") var showTerminalTab = true
    @AppStorage("showFilesTab") var showFilesTab = true
    @AppStorage("showBrowserTab") var showBrowserTab = true
    @AppStorage("showOpenInApp") private var showOpenInApp = true
    @AppStorage("showGitStatus") private var showGitStatus = true
    @AppStorage("showXcodeBuild") private var showXcodeBuild = true
    @AppStorage("zenModeEnabled") private var zenModeEnabled = false
    @State var selectedTab = "chat"
    @State var lastOpenedApp: DetectedApp?
    let worktreeRuntime: WorktreeRuntime
    @ObservedObject var gitSummaryStore: GitSummaryStore
    @ObservedObject private var xcodeBuildManager: XcodeBuildStore
    @StateObject var tabConfig = TabConfigurationStore.shared
    @State var fileSearchWindowController: FileSearchWindowController?
    @State var fileToOpenFromSearch: String?
    @State private var cachedTerminalBackgroundColor: Color?
    @State var hasLoadedTabState = false
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

    var visibleTabIds: [String] {
        tabConfig.tabOrder
            .map(\.id)
            .filter { isTabVisible($0) }
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
    
    private func validateSelectedTab() {
        let visibleTabs = tabConfig.tabOrder.filter { isTabVisible($0.id) }
        if !visibleTabs.contains(where: { $0.id == selectedTab }) {
            selectedTab = visibleTabs.first?.id ?? "files"
        }
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

}

#Preview {
    WorktreeDetailView(
        worktree: Worktree(),
        repositoryManager: WorkspaceRepositoryStore(viewContext: PersistenceController.preview.container.viewContext),
        tabStateManager: WorktreeTabStateStore(),
        gitChangesContext: .constant(nil)
    )
}
