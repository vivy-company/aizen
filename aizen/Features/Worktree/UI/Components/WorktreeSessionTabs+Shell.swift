import ACP
import SwiftUI

extension SessionTabsScrollView {
    var body: some View {
        HStack(spacing: 4) {
            HStack(spacing: 4) {
                NavigationArrowButton(
                    icon: "chevron.left",
                    action: scrollToPrevious,
                    help: "Previous tab"
                )

                NavigationArrowButton(
                    icon: "chevron.right",
                    action: scrollToNext,
                    help: "Next tab"
                )
            }
            .padding(.leading, 8)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        if selectedTab == "chat" && !chatSessions.isEmpty {
                            ForEach(chatSessions) { session in
                                let index = chatSessions.firstIndex(where: { $0.id == session.id }) ?? 0
                                ChatSessionTabItemView(
                                    session: session,
                                    isSelected: selectedChatSessionId == session.id,
                                    onSelect: { selectedChatSessionId = session.id },
                                    onClose: { onCloseChatSession(session) }
                                )
                                .id(session.id)
                                .contextMenu {
                                    chatContextMenu(session: session, index: index)
                                }
                            }
                        } else if selectedTab == "terminal" && !terminalSessions.isEmpty {
                            ForEach(terminalSessions) { session in
                                let index = terminalSessions.firstIndex(where: { $0.id == session.id }) ?? 0
                                TerminalSessionTabItemView(
                                    session: session,
                                    isSelected: selectedTerminalSessionId == session.id,
                                    onSelect: { selectedTerminalSessionId = session.id },
                                    onClose: { requestCloseTerminalSession(session) }
                                )
                                .id(session.id)
                                .contextMenu {
                                    terminalContextMenu(session: session, index: index)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 6)
                }
                .frame(maxWidth: 600, maxHeight: 36)
                .onAppear {
                    scrollViewProxy = proxy
                }
                .background(WheelScrollHandler { _ in })
            }

            NewTabButton(
                selectedTab: selectedTab,
                onCreateChatSession: onCreateChatSession,
                onCreateTerminalSession: onCreateTerminalSession,
                onCreateChatWithAgent: onCreateChatWithAgent,
                onCreateTerminalWithPreset: onCreateTerminalWithPreset
            )
            .padding(.trailing, 8)
        }
        .alert("Close Terminal?", isPresented: $showCloseConfirmation) {
            Button("Cancel", role: .cancel) {
                sessionToClose = nil
            }
            Button("Close", role: .destructive) {
                if let session = sessionToClose {
                    onCloseTerminalSession(session)
                    sessionToClose = nil
                }
            }
            .keyboardShortcut(.defaultAction)
        } message: {
            Text("A process is still running in this terminal. Are you sure you want to close it?")
        }
    }

    func requestCloseTerminalSession(_ session: TerminalSession) {
        guard let sessionId = session.id else {
            onCloseTerminalSession(session)
            return
        }

        let paneIds: [String]
        if let layoutJSON = session.splitLayout,
           let layout = SplitLayoutHelper.decode(layoutJSON) {
            paneIds = layout.allPaneIds()
        } else {
            paneIds = ["main"]
        }

        if TerminalRuntimeStore.shared.hasRunningProcess(for: sessionId, paneIds: paneIds) {
            sessionToClose = session
            showCloseConfirmation = true
        } else {
            onCloseTerminalSession(session)
        }
    }

    func scrollToPrevious() {
        if selectedTab == "chat", let currentId = selectedChatSessionId,
           let currentIndex = chatSessions.firstIndex(where: { $0.id == currentId }),
           currentIndex > 0 {
            let prevSession = chatSessions[currentIndex - 1]
            selectedChatSessionId = prevSession.id
            scrollViewProxy?.scrollTo(prevSession.id, anchor: .center)
        } else if selectedTab == "terminal", let currentId = selectedTerminalSessionId,
                  let currentIndex = terminalSessions.firstIndex(where: { $0.id == currentId }),
                  currentIndex > 0 {
            let prevSession = terminalSessions[currentIndex - 1]
            selectedTerminalSessionId = prevSession.id
            scrollViewProxy?.scrollTo(prevSession.id, anchor: .center)
        }
    }

    func scrollToNext() {
        if selectedTab == "chat", let currentId = selectedChatSessionId,
           let currentIndex = chatSessions.firstIndex(where: { $0.id == currentId }),
           currentIndex < chatSessions.count - 1 {
            let nextSession = chatSessions[currentIndex + 1]
            selectedChatSessionId = nextSession.id
            scrollViewProxy?.scrollTo(nextSession.id, anchor: .center)
        } else if selectedTab == "terminal", let currentId = selectedTerminalSessionId,
                  let currentIndex = terminalSessions.firstIndex(where: { $0.id == currentId }),
                  currentIndex < terminalSessions.count - 1 {
            let nextSession = terminalSessions[currentIndex + 1]
            selectedTerminalSessionId = nextSession.id
            scrollViewProxy?.scrollTo(nextSession.id, anchor: .center)
        }
    }
}
