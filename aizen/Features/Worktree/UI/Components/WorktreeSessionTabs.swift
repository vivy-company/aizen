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

    @State private var scrollViewProxy: ScrollViewProxy?
    @State private var sessionToClose: TerminalSession?
    @State private var showCloseConfirmation = false

    var body: some View {
        HStack(spacing: 4) {
            // Navigation arrows group
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

            // Tabs ScrollView with horizontal scroll on vertical wheel
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

            // New tab button - fixed position outside scroll view
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

    // MARK: - Terminal Close with Confirmation

    func requestCloseTerminalSession(_ session: TerminalSession) {
        guard let sessionId = session.id else {
            onCloseTerminalSession(session)
            return
        }

        // Get pane IDs from layout
        let paneIds: [String]
        if let layoutJSON = session.splitLayout,
           let layout = SplitLayoutHelper.decode(layoutJSON) {
            paneIds = layout.allPaneIds()
        } else {
            paneIds = ["main"]
        }

        // Check if any pane has a running process
        if TerminalRuntimeStore.shared.hasRunningProcess(for: sessionId, paneIds: paneIds) {
            sessionToClose = session
            showCloseConfirmation = true
        } else {
            onCloseTerminalSession(session)
        }
    }

    // MARK: - Scroll Navigation

    private func scrollToPrevious() {
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

    private func scrollToNext() {
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

// MARK: - New Tab Button

struct NewTabButton: View {
    let selectedTab: String
    let onCreateChatSession: () -> Void
    let onCreateTerminalSession: () -> Void
    var onCreateChatWithAgent: ((String) -> Void)?
    var onCreateTerminalWithPreset: ((TerminalPreset) -> Void)?

    @StateObject private var presetManager = TerminalPresetStore.shared
    @State private var enabledAgents: [AgentMetadata] = []
    @State private var isHovering = false
    @State private var clickTrigger = 0

    var body: some View {
        // Use Menu with primaryAction for chat tab when agents exist
        if selectedTab == "chat" && !enabledAgents.isEmpty {
            Menu {
                ForEach(enabledAgents, id: \.id) { agentMetadata in
                    Button {
                        onCreateChatWithAgent?(agentMetadata.id)
                    } label: {
                        HStack {
                            AgentIconView(metadata: agentMetadata, size: 14)
                            Text(agentMetadata.name)
                        }
                    }
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11))
                    .frame(width: 24, height: 24)
                    .background(
                        isHovering ? Color(nsColor: .separatorColor).opacity(0.5) : Color.clear,
                        in: Circle()
                    )
            } primaryAction: {
                clickTrigger += 1
                onCreateChatSession()
            }
            .menuStyle(.button)
            .menuIndicator(.visible)
            .buttonStyle(.plain)
            .onHover { hovering in
                isHovering = hovering
            }
            .help("Click for new chat, or click arrow for agents")
            .onAppear {
                enabledAgents = AgentRegistry.shared.getEnabledAgents()
            }
            .onReceive(NotificationCenter.default.publisher(for: .agentMetadataDidChange)) { _ in
                enabledAgents = AgentRegistry.shared.getEnabledAgents()
            }
        } else if selectedTab == "terminal" && !presetManager.presets.isEmpty {
            // Use Menu with primaryAction when presets exist for terminal tab
            Menu {
                Button {
                    onCreateTerminalSession()
                } label: {
                    Label("New Terminal", systemImage: "terminal")
                }

                Divider()

                ForEach(presetManager.presets) { preset in
                    Button {
                        onCreateTerminalWithPreset?(preset)
                    } label: {
                        Label(preset.name, systemImage: preset.icon)
                    }
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11))
                    .frame(width: 24, height: 24)
                    .background(
                        isHovering ? Color(nsColor: .separatorColor).opacity(0.5) : Color.clear,
                        in: Circle()
                    )
            } primaryAction: {
                clickTrigger += 1
                onCreateTerminalSession()
            }
            .menuStyle(.button)
            .menuIndicator(.visible)
            .buttonStyle(.plain)
            .onHover { hovering in
                isHovering = hovering
            }
            .help("Click for new terminal, or click arrow for presets")
        } else {
            // Simple button when no agents/presets
            let button = Button {
                clickTrigger += 1
                if selectedTab == "chat" {
                    onCreateChatSession()
                } else {
                    onCreateTerminalSession()
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11))
                    .frame(width: 24, height: 24)
                    .background(
                        isHovering ? Color(nsColor: .separatorColor).opacity(0.5) : Color.clear,
                        in: Circle()
                    )
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isHovering = hovering
            }
            .help("New \(selectedTab == "chat" ? "Chat" : "Terminal") Session")
            .onAppear {
                if selectedTab == "chat" {
                    enabledAgents = AgentRegistry.shared.getEnabledAgents()
                }
            }

            if #available(macOS 14.0, *) {
                button.symbolEffect(.bounce, value: clickTrigger)
            } else {
                button
            }
        }
    }
}
