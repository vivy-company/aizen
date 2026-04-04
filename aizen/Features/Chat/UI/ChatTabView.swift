//
//  ChatTabView.swift
//  aizen
//
//  Chat tab management and empty state
//

import ACP
import AppKit
import CoreData
import os.log
import SwiftUI

struct ChatTabView: View {
    let worktree: Worktree
    let repositoryManager: WorkspaceRepositoryStore
    @Binding var selectedSessionId: UUID?
    @Binding var selectedTerminalSessionId: UUID?
    @Binding var selectedBrowserSessionId: UUID?

    @Environment(\.managedObjectContext) var viewContext
    let sessionManager = ChatSessionRegistry.shared
    let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen", category: "ChatTabView")
    @State var enabledAgents: [AgentMetadata] = []
    @State var cachedSessionIds: [UUID] = []
    // Keep only the active chat session mounted to avoid hidden view layout churn.
    let maxCachedSessions = 1
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
        sessions.compactMap(\.id)
    }

    @FetchRequest var sessions: FetchedResults<ChatSession>
    @FetchRequest private var recentSessions: FetchedResults<ChatSession>

    init(
        worktree: Worktree,
        repositoryManager: WorkspaceRepositoryStore,
        selectedSessionId: Binding<UUID?>,
        selectedTerminalSessionId: Binding<UUID?>,
        selectedBrowserSessionId: Binding<UUID?>
    ) {
        self.worktree = worktree
        self.repositoryManager = repositoryManager
        self._selectedSessionId = selectedSessionId
        self._selectedTerminalSessionId = selectedTerminalSessionId
        self._selectedBrowserSessionId = selectedBrowserSessionId

        // Handle deleted worktree gracefully - use impossible predicate to return empty results
        let predicate: NSPredicate
        if let worktreeId = worktree.id {
            predicate = NSPredicate(format: "worktree.id == %@ AND archived == NO", worktreeId as CVarArg)
        } else {
            predicate = NSPredicate(value: false)
        }

        self._sessions = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \ChatSession.createdAt, ascending: true)],
            predicate: predicate,
            animation: nil
        )

        let recentRequest: NSFetchRequest<ChatSession> = ChatSession.fetchRequest()
        if let worktreeId = worktree.id {
            recentRequest.predicate = NSPredicate(
                format: "worktree.id == %@ AND SUBQUERY(messages, $m, $m.role == 'user').@count > 0",
                worktreeId as CVarArg
            )
        } else {
            recentRequest.predicate = NSPredicate(value: false)
        }
        recentRequest.sortDescriptors = [NSSortDescriptor(key: "lastMessageAt", ascending: false)]
        recentRequest.fetchLimit = recentSessionsLimit
        recentRequest.relationshipKeyPathsForPrefetching = ["worktree"]
        self._recentSessions = FetchRequest(fetchRequest: recentRequest, animation: nil)
    }

    var body: some View {
        Group {
            if sessions.isEmpty {
                ChatEmptyStateView(
                    enabledAgents: enabledAgents,
                    recentSessions: Array(recentSessions),
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
