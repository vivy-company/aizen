import SwiftUI

extension WorktreeDetailView {
    var terminalHostIdentity: String {
        let sessionIds = sessionManager.terminalSessions.compactMap { $0.id?.uuidString }.joined(separator: ",")
        let selectedSessionId = viewModel.selectedTerminalSessionId?.uuidString ?? "nil"
        let isTerminalVisible = selectedTab == "terminal"
        return "\(worktree.objectID.uriRepresentation().absoluteString)|\(selectedSessionId)|\(sessionIds)|\(isTerminalVisible)"
    }

    var sessionManager: WorktreeSessionCoordinator {
        WorktreeSessionCoordinator(
            worktree: worktree,
            viewModel: viewModel,
            logger: logger
        )
    }

    var browserSessions: [BrowserSession] {
        viewModel.browserSessions
    }

    var mountedTabIds: [String] {
        visibleTabIds.filter(scene.isTabWarm(_:))
    }

    var hasActiveSessions: Bool {
        (selectedTab == "chat" && !sessionManager.chatSessions.isEmpty) ||
        (selectedTab == "terminal" && !sessionManager.terminalSessions.isEmpty) ||
        (selectedTab == "browser" && !browserSessions.isEmpty)
    }

    var shouldShowSessionToolbar: Bool {
        selectedTab != "files" && selectedTab != "browser" && hasActiveSessions
    }

    @ViewBuilder
    var contentView: some View {
        ZStack {
            ForEach(mountedTabIds, id: \.self) { tabId in
                tabView(for: tabId)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(selectedTab == tabId ? 1 : 0)
                    .allowsHitTesting(selectedTab == tabId)
                    .accessibilityHidden(selectedTab != tabId)
                    .zIndex(selectedTab == tabId ? 1 : 0)
            }
        }
    }

    @ViewBuilder
    var mainContentWithSidebars: some View {
        ZStack(alignment: .top) {
            contentView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(detailSurfaceColor)

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
        .task {
            applyPendingNavigationDestinationIfNeeded()
        }
        .onChange(of: navigationSelectionStore.pendingWorktreeDestination) { _, _ in
            applyPendingNavigationDestinationIfNeeded()
        }
    }

    @ViewBuilder
    private func tabView(for tabId: String) -> some View {
        switch tabId {
        case "chat":
            ChatTabView(
                worktree: worktree,
                repositoryManager: repositoryManager,
                chatSessions: viewModel.chatSessions,
                recentSessions: viewModel.recentChatSessions,
                terminalSessions: viewModel.terminalSessions,
                browserSessions: viewModel.browserSessions,
                fileBrowserStore: scene.fileBrowserStore,
                browserSessionStore: scene.browserSessionStore,
                selectedSessionId: $viewModel.selectedChatSessionId,
                selectedTerminalSessionId: $viewModel.selectedTerminalSessionId,
                selectedBrowserSessionId: $viewModel.selectedBrowserSessionId,
                chatStoreProvider: scene.chatStore(for:)
            )
        case "terminal":
            AizenTerminalRootContainer(identity: terminalHostIdentity) {
                TerminalTabView(
                    worktree: worktree,
                    sessions: sessionManager.terminalSessions,
                    isVisible: selectedTab == "terminal",
                    selectedSessionId: $viewModel.selectedTerminalSessionId,
                    repositoryManager: repositoryManager
                )
            }
        case "files":
            FileTabView(
                worktree: worktree,
                fileToOpenFromSearch: $fileToOpenFromSearch,
                store: scene.fileBrowserStore
            )
        case "browser":
            if let browserSessionStore = scene.browserSessionStore {
                BrowserTabView(
                    manager: browserSessionStore,
                    selectedSessionId: $viewModel.selectedBrowserSessionId,
                    isSelected: selectedTab == "browser"
                )
                .id(ObjectIdentifier(browserSessionStore))
            }
        default:
            EmptyView()
        }
    }
}
