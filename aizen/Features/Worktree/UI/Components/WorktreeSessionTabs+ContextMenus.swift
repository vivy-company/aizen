//
//  WorktreeSessionTabs+ContextMenus.swift
//  aizen
//
//  Context menus and bulk tab actions for session tabs
//

import SwiftUI

extension SessionTabsScrollView {
    @ViewBuilder
    func chatContextMenu(session: ChatSession, index: Int) -> some View {
        Button("Close Tab") {
            onCloseChatSession(session)
        }

        if index > 0 {
            Button("Close All to the Left") {
                closeAllChatToLeft(index: index)
            }
        }

        if index < chatSessions.count - 1 {
            Button("Close All to the Right") {
                closeAllChatToRight(index: index)
            }
        }

        if chatSessions.count > 1 {
            Button("Close Other Tabs") {
                closeOtherChatTabs(session: session)
            }
        }
    }

    @ViewBuilder
    func terminalContextMenu(session: TerminalSession, index: Int) -> some View {
        Button("Close Tab") {
            requestCloseTerminalSession(session)
        }

        if index > 0 {
            Button("Close All to the Left") {
                closeAllTerminalToLeft(index: index)
            }
        }

        if index < terminalSessions.count - 1 {
            Button("Close All to the Right") {
                closeAllTerminalToRight(index: index)
            }
        }

        if terminalSessions.count > 1 {
            Button("Close Other Tabs") {
                closeOtherTerminalTabs(session: session)
            }
        }
    }

    func closeAllChatToLeft(index: Int) {
        for i in (0..<index).reversed() {
            onCloseChatSession(chatSessions[i])
        }
    }

    func closeAllChatToRight(index: Int) {
        for i in ((index + 1)..<chatSessions.count).reversed() {
            onCloseChatSession(chatSessions[i])
        }
    }

    func closeOtherChatTabs(session: ChatSession) {
        chatSessions.filter { $0.id != session.id }.forEach { onCloseChatSession($0) }
    }

    func closeAllTerminalToLeft(index: Int) {
        for i in (0..<index).reversed() {
            onCloseTerminalSession(terminalSessions[i])
        }
    }

    func closeAllTerminalToRight(index: Int) {
        for i in ((index + 1)..<terminalSessions.count).reversed() {
            onCloseTerminalSession(terminalSessions[i])
        }
    }

    func closeOtherTerminalTabs(session: TerminalSession) {
        terminalSessions.filter { $0.id != session.id }.forEach { onCloseTerminalSession($0) }
    }
}
