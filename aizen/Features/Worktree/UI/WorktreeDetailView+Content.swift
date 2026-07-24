import SwiftUI

extension WorktreeDetailView {
    @ViewBuilder
    var contentView: some View {
        WorkspaceView(scene: scene, searchOpenRequest: $searchOpenRequest)
    }

    @ViewBuilder
    var mainContentWithSidebars: some View {
        ZStack(alignment: .top) {
            contentView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(detailSurfaceColor)

            PermissionBannerView(
                currentChatSessionId: focusedChatSessionId,
                onNavigate: { sessionId in
                    navigateToChatSession(sessionId)
                }
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .projectSearchShortcut)) { notification in
            let rawValue = notification.userInfo?[ProjectSearchShortcutUserInfoKey.mode] as? String
            let mode = rawValue.flatMap(ProjectSearchMode.init(rawValue:)) ?? .files
            showProjectSearch(mode: mode)
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

    /// Chat session backing the focused pane, if the focused pane is a chat.
    var focusedChatSessionId: UUID? {
        guard let pane = scene.workspace.focusedPane, pane.kind == .chat else { return nil }
        return pane.sessionId
    }
}
