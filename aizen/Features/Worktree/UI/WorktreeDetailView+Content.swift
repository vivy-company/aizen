import SwiftUI

extension WorktreeDetailView {
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
        Group {
            if selectedTab == "chat" {
                ChatTabView(
                    worktree: worktree,
                    repositoryManager: repositoryManager,
                    chatSessions: viewModel.chatSessions,
                    recentSessions: viewModel.recentChatSessions,
                    terminalSessions: viewModel.terminalSessions,
                    browserSessions: viewModel.browserSessions,
                    selectedSessionId: $viewModel.selectedChatSessionId,
                    selectedTerminalSessionId: $viewModel.selectedTerminalSessionId,
                    selectedBrowserSessionId: $viewModel.selectedBrowserSessionId
                )
            } else if selectedTab == "terminal" {
                AizenTerminalRootContainer {
                    TerminalTabView(
                        worktree: worktree,
                        sessions: sessionManager.terminalSessions,
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
}
