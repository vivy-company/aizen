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
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen", category: "ChatTabView")
    @State private var enabledAgents: [AgentMetadata] = []
    @State var cachedSessionIds: [UUID] = []
    // Keep only the active chat session mounted to avoid hidden view layout churn.
    private let maxCachedSessions = 1
    private let recentSessionsLimit = 3

    // Companion panel state (persisted) - Left
    @AppStorage("companionLeftPanelType") private var leftPanelType: String = ""
    @AppStorage("companionLeftPanelWidth") private var leftPanelWidthStored: Double = 400
    @State var leftPanelWidth: Double = 400

    // Companion panel state (persisted) - Right
    @AppStorage("companionRightPanelType") private var rightPanelType: String = ""
    @AppStorage("companionRightPanelWidth") private var rightPanelWidthStored: Double = 400
    @State var rightPanelWidth: Double = 400

    @State private var didLoadWidths = false
    @State var isResizingCompanion = false

    let minPanelWidth: CGFloat = 250
    let minCenterWidth: CGFloat = 360
    let dividerWidth: CGFloat = 1
    let maxPanelWidthRatio: CGFloat = 0.75
    private let companionCoordinateSpace = "companionSplit"

    var leftPanel: CompanionPanel? {
        get { CompanionPanel(rawValue: leftPanelType) }
        nonmutating set { leftPanelType = newValue?.rawValue ?? "" }
    }

    var rightPanel: CompanionPanel? {
        get { CompanionPanel(rawValue: rightPanelType) }
        nonmutating set { rightPanelType = newValue?.rawValue ?? "" }
    }

    // Panels available for each side (excluding what's on the other side)
    private var availableForLeft: [CompanionPanel] {
        CompanionPanel.allCases.filter { $0.rawValue != rightPanelType }
    }

    private var availableForRight: [CompanionPanel] {
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

    @ViewBuilder
    private var chatContentWithCompanion: some View {
        GeometryReader { geometry in
            let toolbarInset = resolvedToolbarInset(from: geometry)
            HStack(spacing: 0) {
                // LEFT PANEL
                if let panel = leftPanel {
                    CompanionPanelView(
                        panel: panel,
                        worktree: worktree,
                        repositoryManager: repositoryManager,
                        side: .left,
                        onClose: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                leftPanelType = ""
                            }
                        },
                        isResizing: isResizingCompanion,
                        terminalSessionId: $selectedTerminalSessionId,
                        browserSessionId: $selectedBrowserSessionId
                    )
                    .padding(.top, toolbarInset)
                    .frame(width: CGFloat(leftPanelWidth))
                    .animation(nil, value: leftPanelWidth)
                    .transition(.move(edge: .leading).combined(with: .opacity))

                    CompanionDivider(
                        panelWidth: $leftPanelWidth,
                        minWidth: minPanelWidth,
                        maxWidth: maxLeftWidth(containerWidth: geometry.size.width, rightWidth: CGFloat(rightPanelWidth)),
                        containerWidth: geometry.size.width,
                        coordinateSpace: companionCoordinateSpace,
                        side: .left,
                        isDragging: $isResizingCompanion,
                        onDragEnd: { leftPanelWidthStored = leftPanelWidth }
                    )
                }

                // CHAT (center)
                chatSessionsStack
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .leading) {
                        if leftPanel == nil {
                            CompanionRailView(
                                side: .left,
                                availablePanels: availableForLeft,
                                onSelect: { leftPanelType = $0.rawValue }
                            )
                        }
                    }
                    .overlay(alignment: .trailing) {
                        if rightPanel == nil {
                            CompanionRailView(
                                side: .right,
                                availablePanels: availableForRight,
                                onSelect: { rightPanelType = $0.rawValue }
                            )
                        }
                    }
                    .padding(.top, toolbarInset)

                // RIGHT PANEL
                if let panel = rightPanel {
                    CompanionDivider(
                        panelWidth: $rightPanelWidth,
                        minWidth: minPanelWidth,
                        maxWidth: maxRightWidth(containerWidth: geometry.size.width, leftWidth: CGFloat(leftPanelWidth)),
                        containerWidth: geometry.size.width,
                        coordinateSpace: companionCoordinateSpace,
                        side: .right,
                        isDragging: $isResizingCompanion,
                        onDragEnd: { rightPanelWidthStored = rightPanelWidth }
                    )

                    CompanionPanelView(
                        panel: panel,
                        worktree: worktree,
                        repositoryManager: repositoryManager,
                        side: .right,
                        onClose: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                rightPanelType = ""
                            }
                        },
                        isResizing: isResizingCompanion,
                        terminalSessionId: $selectedTerminalSessionId,
                        browserSessionId: $selectedBrowserSessionId
                    )
                    .padding(.top, toolbarInset)
                    .frame(width: CGFloat(rightPanelWidth))
                    .animation(nil, value: rightPanelWidth)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: leftPanelType)
            .animation(.easeInOut(duration: 0.2), value: rightPanelType)
            .animation(nil, value: leftPanelWidth)
            .animation(nil, value: rightPanelWidth)
            .transaction { transaction in
                if isResizingCompanion {
                    transaction.disablesAnimations = true
                }
            }
            .ignoresSafeArea(.container, edges: .top)
            .coordinateSpace(name: companionCoordinateSpace)
            .onAppear {
                if !didLoadWidths {
                    leftPanelWidth = leftPanelWidthStored
                    rightPanelWidth = rightPanelWidthStored
                    clampPanelWidths(containerWidth: geometry.size.width)
                    didLoadWidths = true
                }
            }
            .task(id: geometry.size.width) {
                // Defer to next run loop to break synchronous layout feedback cycle.
                // Writing @State during layout can re-trigger the same layout pass.
                DispatchQueue.main.async {
                    clampPanelWidths(containerWidth: geometry.size.width)
                }
            }
            .task(id: leftPanelType) {
                DispatchQueue.main.async {
                    clampPanelWidths(containerWidth: geometry.size.width)
                }
            }
            .task(id: rightPanelType) {
                DispatchQueue.main.async {
                    clampPanelWidths(containerWidth: geometry.size.width)
                }
            }
        }
    }

    private func syncSelectionAndCache() {
        if selectedSessionId == nil {
            selectedSessionId = sessions.last?.id
        } else if let currentId = selectedSessionId,
                  !sessions.contains(where: { $0.id == currentId }) {
            selectedSessionId = sessions.last?.id
        }
        pruneCache()
        updateCacheForSelection()
    }

    private func updateCacheForSelection() {
        guard let selectedId = selectedSessionId else { return }
        guard sessions.contains(where: { $0.id == selectedId }) else { return }
        cachedSessionIds.removeAll { $0 == selectedId }
        cachedSessionIds.append(selectedId)
        if cachedSessionIds.count > maxCachedSessions {
            cachedSessionIds.removeFirst(cachedSessionIds.count - maxCachedSessions)
        }
    }

    private func pruneCache() {
        let validIds = Set(sessions.compactMap { $0.id })
        cachedSessionIds.removeAll { !validIds.contains($0) }
    }

    private func loadEnabledAgents() {
        Task {
            enabledAgents = AgentRegistry.shared.getEnabledAgents()
        }
    }

    private func resumeRecentSession(_ session: ChatSession) {
        guard let sessionId = session.id else { return }
        guard session.worktree?.id == worktree.id else { return }

        if session.archived {
            session.archived = false
            do {
                try viewContext.save()
                viewContext.refresh(session, mergeChanges: false)
            } catch {
                logger.error("Failed to unarchive session: \(error.localizedDescription)")
                return
            }
        }

        guard let worktree = session.worktree, !worktree.isDeleted else { return }
        guard let worktreeId = worktree.id else { return }
        guard let worktreePath = worktree.path, FileManager.default.fileExists(atPath: worktreePath) else { return }

        NotificationCenter.default.post(
            name: .resumeChatSession,
            object: nil,
            userInfo: [
                "chatSessionId": sessionId,
                "worktreeId": worktreeId
            ]
        )
    }

    private func createNewSession(withAgent agent: String) {
        guard let context = worktree.managedObjectContext else { return }

        let session = ChatSession(context: context)
        session.id = UUID()
        session.agentName = agent
        session.archived = false
        session.createdAt = Date()
        session.worktree = worktree

        // Use agent display name instead of ID
        let displayName = AgentRegistry.shared.getMetadata(for: agent)?.name ?? agent.capitalized
        session.title = displayName

        do {
            try context.save()
            // Update binding immediately (synchronous post-save)
            selectedSessionId = session.id
            logger.info("Created new chat session: \(session.id?.uuidString ?? "unknown")")
        } catch {
            logger.error("Failed to create chat session: \(error.localizedDescription)")
        }
    }
}
