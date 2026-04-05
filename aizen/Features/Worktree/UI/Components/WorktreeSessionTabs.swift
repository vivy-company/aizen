//
//  WorktreeSessionTabs.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 04.11.25.
//

import ACP
import SwiftUI

// MARK: - Session Tabs ScrollView

struct SessionTabsScrollView: View {
    let selectedTab: String
    let chatSessions: [ChatSession]
    let terminalSessions: [TerminalSession]
    @Binding var selectedChatSessionId: UUID?
    @Binding var selectedTerminalSessionId: UUID?
    let onCloseChatSession: (ChatSession) -> Void
    let onCloseTerminalSession: (TerminalSession) -> Void
    let onCreateChatSession: () -> Void
    let onCreateTerminalSession: () -> Void
    var onCreateChatWithAgent: ((String) -> Void)?
    var onCreateTerminalWithPreset: ((TerminalPreset) -> Void)?

    @State var scrollViewProxy: ScrollViewProxy?
    @State var sessionToClose: TerminalSession?
    @State var showCloseConfirmation = false

}
