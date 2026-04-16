//
//  ChatTabView.swift
//  aizen
//
//  Chat tab management and empty state
//

import ACP
import AppKit
import os.log
import SwiftUI

struct ChatTabView: View {
    let worktree: Worktree
    let repositoryManager: WorkspaceRepositoryStore
    let chatSessions: [ChatSession]
    let recentSessions: [ChatSession]
    let terminalSessions: [TerminalSession]
    let browserSessions: [BrowserSession]
    let fileBrowserStore: FileBrowserStore?
    let browserSessionStore: BrowserSessionStore?
    @Binding var selectedSessionId: UUID?
    @Binding var selectedTerminalSessionId: UUID?
    @Binding var selectedBrowserSessionId: UUID?
    let chatStoreProvider: (ChatSession) -> ChatSessionStore

    @Environment(\.managedObjectContext) var viewContext
    let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen", category: "ChatTabView")
    @State var enabledAgents: [AgentMetadata] = []
    @State var cachedSessionIds: [UUID] = []
    let maxCachedSessions = 3
    private let recentSessionsLimit = 3

    // Companion panel state (persisted) - Left
    @AppStorage("companionLeftPanelType") var leftPanelType: String = ""
    @AppStorage("companionLeftPanelWidth") var leftPanelWidthStored: Double = 400
    @State var leftPanelWidth: Double = 400

    // Companion panel state (persisted) - Right
    @AppStorage("companionRightPanelType") var rightPanelType: String = ""
    @AppStorage("companionRightPanelWidth") var rightPanelWidthStored: Double = 400
    @State var rightPanelWidth: Double = 400

    @State var didLoadWidths = false
    @State var isResizingCompanion = false

    let minPanelWidth: CGFloat = 250
    let minCenterWidth: CGFloat = 360
    let dividerWidth: CGFloat = 1
    let maxPanelWidthRatio: CGFloat = 0.75
    let companionCoordinateSpace = "companionSplit"

    var leftPanel: CompanionPanel? {
        get { CompanionPanel(rawValue: leftPanelType) }
        nonmutating set { leftPanelType = newValue?.rawValue ?? "" }
    }

    var rightPanel: CompanionPanel? {
        get { CompanionPanel(rawValue: rightPanelType) }
        nonmutating set { rightPanelType = newValue?.rawValue ?? "" }
    }

    // Panels available for each side (excluding what's on the other side)
    var availableForLeft: [CompanionPanel] {
        CompanionPanel.allCases.filter { $0.rawValue != rightPanelType }
    }

    var availableForRight: [CompanionPanel] {
        CompanionPanel.allCases.filter { $0.rawValue != leftPanelType }
    }

    private var sessionIdentitySnapshot: [UUID] {
        chatSessions.compactMap(\.id)
    }

    init(
        worktree: Worktree,
        repositoryManager: WorkspaceRepositoryStore,
        chatSessions: [ChatSession],
        recentSessions: [ChatSession],
        terminalSessions: [TerminalSession],
        browserSessions: [BrowserSession],
        fileBrowserStore: FileBrowserStore?,
        browserSessionStore: BrowserSessionStore?,
        selectedSessionId: Binding<UUID?>,
        selectedTerminalSessionId: Binding<UUID?>,
        selectedBrowserSessionId: Binding<UUID?>,
        chatStoreProvider: @escaping (ChatSession) -> ChatSessionStore
    ) {
        self.worktree = worktree
        self.repositoryManager = repositoryManager
        self.chatSessions = chatSessions
        self.recentSessions = recentSessions
        self.terminalSessions = terminalSessions
        self.browserSessions = browserSessions
        self.fileBrowserStore = fileBrowserStore
        self.browserSessionStore = browserSessionStore
        self._selectedSessionId = selectedSessionId
        self._selectedTerminalSessionId = selectedTerminalSessionId
        self._selectedBrowserSessionId = selectedBrowserSessionId
        self.chatStoreProvider = chatStoreProvider
    }

    var body: some View {
        Group {
            if chatSessions.isEmpty {
                ChatEmptyStateView(
                    enabledAgents: enabledAgents,
                    recentSessions: recentSessions,
                    recentSessionsLimit: recentSessionsLimit,
                    onAgentSelect: createNewSession(withAgent:),
                    onShowMore: {
                        SessionsWindowController.shared.show(context: viewContext, worktreeId: worktree.id)
                    },
                    onResumeRecentSession: resumeRecentSession(_:)
                )
                .onAppear {
                    loadEnabledAgents()
                }
                .onReceive(NotificationCenter.default.publisher(for: .agentMetadataDidChange)) { _ in
                    loadEnabledAgents()
                }
            } else {
                chatContentWithCompanion
                    .onAppear {
                        syncSelectionAndCache()
                    }
                    .task(id: selectedSessionId) {
                        updateCacheForSelection()
                    }
                    .task(id: sessionIdentitySnapshot) {
                        syncSelectionAndCache()
                    }
            }
        }
    }

}
