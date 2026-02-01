//
//  WorktreeSessionTabs.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 04.11.25.
//

import ACP
import SwiftUI

// MARK: - Terminal Persistence Indicator

struct TerminalPersistenceIndicator: View {
    @AppStorage("terminalSessionPersistence") private var sessionPersistence = false

    var body: some View {
        if sessionPersistence {
            Image(systemName: "pin.fill")
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
                .help("Session persists across app restarts")
        }
    }
}

// MARK: - Pending Permission Indicator

struct PendingPermissionIndicator: View {
    @State private var isAnimating = false

    var body: some View {
        Circle()
            .fill(Color.orange)
            .frame(width: 8, height: 8)
            .opacity(isAnimating ? 0.4 : 1.0)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isAnimating)
            .onAppear { isAnimating = true }
            .help("Pending permission request - click to respond")
    }
}

// MARK: - Session Tab Button

struct SessionTabButton<Content: View>: View {
    let isSelected: Bool
    let action: () -> Void
    let content: Content

    @State private var isHovering = false

    init(isSelected: Bool, action: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.isSelected = isSelected
        self.action = action
        self.content = content()
    }


    var body: some View {
        Button(action: action) {
            content
                .padding(.leading, 6)
                .padding(.trailing, 12)
                .padding(.vertical, 6)
                .background(
                    isSelected ?
                    Color(nsColor: .separatorColor) :
                    (isHovering ? Color(nsColor: .separatorColor).opacity(0.5) : Color.clear),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

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

    @ObservedObject private var sessionManager = ChatSessionManager.shared

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
                                chatTabView(session: session)
                                    .id(session.id)
                                    .contextMenu {
                                        chatContextMenu(session: session, index: index)
                                    }
                            }
                        } else if selectedTab == "terminal" && !terminalSessions.isEmpty {
                            ForEach(terminalSessions) { session in
                                let index = terminalSessions.firstIndex(where: { $0.id == session.id }) ?? 0
                                terminalTabView(session: session)
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
        } message: {
            Text("A process is still running in this terminal. Are you sure you want to close it?")
        }
    }

    // MARK: - Terminal Close with Confirmation

    private func requestCloseTerminalSession(_ session: TerminalSession) {
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
        if TerminalSessionManager.shared.hasRunningProcess(for: sessionId, paneIds: paneIds) {
            sessionToClose = session
            showCloseConfirmation = true
        } else {
            onCloseTerminalSession(session)
        }
    }

    // MARK: - Chat Tab View

    @ViewBuilder
    private func chatTabView(session: ChatSession) -> some View {
        let hasPendingPermission = session.id.map { sessionManager.hasPendingPermission(for: $0) } ?? false

        SessionTabButton(
            isSelected: selectedChatSessionId == session.id,
            action: { selectedChatSessionId = session.id }
        ) {
            HStack(spacing: 6) {
                DetailCloseButton(action: { onCloseChatSession(session) }, size: 10)

                AgentIconView(agent: session.agentName ?? "claude", size: 14)

                Text(session.title ?? session.agentName?.capitalized ?? String(localized: "worktree.session.chat"))
                    .font(.callout)

                // Pending permission indicator
                if hasPendingPermission {
                    PendingPermissionIndicator()
                }
            }
        }
    }

    // MARK: - Terminal Tab View

    @ViewBuilder
    private func terminalTabView(session: TerminalSession) -> some View {
        SessionTabButton(
            isSelected: selectedTerminalSessionId == session.id,
            action: { selectedTerminalSessionId = session.id }
        ) {
            HStack(spacing: 6) {
                DetailCloseButton(action: { requestCloseTerminalSession(session) }, size: 10)

                Image(systemName: "terminal")
                    .font(.system(size: 12))

                Text(session.title ?? String(localized: "worktree.session.terminal"))
                    .font(.callout)

                TerminalPersistenceIndicator()
            }
        }
    }

    // MARK: - Context Menus

    @ViewBuilder
    private func chatContextMenu(session: ChatSession, index: Int) -> some View {
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
    private func terminalContextMenu(session: TerminalSession, index: Int) -> some View {
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

    // MARK: - Context Menu Actions

    private func closeAllChatToLeft(index: Int) {
        for i in (0..<index).reversed() {
            onCloseChatSession(chatSessions[i])
        }
    }

    private func closeAllChatToRight(index: Int) {
        for i in ((index + 1)..<chatSessions.count).reversed() {
            onCloseChatSession(chatSessions[i])
        }
    }

    private func closeOtherChatTabs(session: ChatSession) {
        chatSessions.filter { $0.id != session.id }.forEach { onCloseChatSession($0) }
    }

    private func closeAllTerminalToLeft(index: Int) {
        for i in (0..<index).reversed() {
            onCloseTerminalSession(terminalSessions[i])
        }
    }

    private func closeAllTerminalToRight(index: Int) {
        for i in ((index + 1)..<terminalSessions.count).reversed() {
            onCloseTerminalSession(terminalSessions[i])
        }
    }

    private func closeOtherTerminalTabs(session: TerminalSession) {
        terminalSessions.filter { $0.id != session.id }.forEach { onCloseTerminalSession($0) }
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

// MARK: - Navigation Arrow Button

struct NavigationArrowButton: View {
    let icon: String
    let action: () -> Void
    let help: String

    @State private var isHovering = false
    @State private var clickTrigger = 0

    var body: some View {
        let button = Button(action: {
            clickTrigger += 1
            action()
        }) {
            Image(systemName: icon)
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
        .help(help)
        
        if #available(macOS 14.0, *) {
            button.symbolEffect(.bounce, value: clickTrigger)
        } else {
            button
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

    @StateObject private var presetManager = TerminalPresetManager.shared
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

// MARK: - Wheel Scroll Handler

private struct WheelScrollHandler: NSViewRepresentable {
    let onScroll: (CGFloat) -> Void

    func makeNSView(context: Context) -> WheelScrollView {
        let view = WheelScrollView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: WheelScrollView, context: Context) {
        nsView.onScroll = onScroll
    }

    class WheelScrollView: NSView {
        var onScroll: ((CGFloat) -> Void)?

        override func scrollWheel(with event: NSEvent) {
            // Convert vertical scroll to horizontal
            if abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) {
                onScroll?(event.scrollingDeltaY)
            }
            super.scrollWheel(with: event)
        }
    }
}
