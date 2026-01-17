//
//  ChatTabView.swift
//  aizen
//
//  Chat tab management and empty state
//

import SwiftUI
import CoreData
import os.log

struct ChatTabView: View {
    let worktree: Worktree
    let repositoryManager: RepositoryManager
    @Binding var selectedSessionId: UUID?
    @Binding var selectedTerminalSessionId: UUID?
    @Binding var selectedBrowserSessionId: UUID?

    @Environment(\.managedObjectContext) private var viewContext
    private let sessionManager = ChatSessionManager.shared
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen", category: "ChatTabView")
    @State private var enabledAgents: [AgentMetadata] = []
    @State private var cachedSessionIds: [UUID] = []
    private let maxCachedSessions = 10

    // Companion panel state (persisted) - Left
    @AppStorage("companionLeftPanelType") private var leftPanelType: String = ""
    @AppStorage("companionLeftPanelWidth") private var leftPanelWidthStored: Double = 400
    @State private var leftPanelWidth: Double = 400

    // Companion panel state (persisted) - Right
    @AppStorage("companionRightPanelType") private var rightPanelType: String = ""
    @AppStorage("companionRightPanelWidth") private var rightPanelWidthStored: Double = 400
    @State private var rightPanelWidth: Double = 400

    @State private var didLoadWidths = false
    @State private var isResizingCompanion = false

    private let minPanelWidth: CGFloat = 250
    private let minCenterWidth: CGFloat = 360
    private let dividerWidth: CGFloat = 1
    private let maxPanelWidthRatio: CGFloat = 0.75
    private let companionCoordinateSpace = "companionSplit"

    private var leftPanel: CompanionPanel? {
        get { CompanionPanel(rawValue: leftPanelType) }
        nonmutating set { leftPanelType = newValue?.rawValue ?? "" }
    }

    private var rightPanel: CompanionPanel? {
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

    @FetchRequest private var sessions: FetchedResults<ChatSession>

    init(
        worktree: Worktree,
        repositoryManager: RepositoryManager,
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
            predicate = NSPredicate(format: "worktree.id == %@", worktreeId as CVarArg)
        } else {
            predicate = NSPredicate(value: false)
        }

        self._sessions = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \ChatSession.createdAt, ascending: true)],
            predicate: predicate,
            animation: nil
        )
    }

    var body: some View {
        if sessions.isEmpty {
            chatEmptyState
        } else {
            chatContentWithCompanion
                .onAppear {
                    syncSelectionAndCache()
                }
                .onChange(of: selectedSessionId) { _ in
                    updateCacheForSelection()
                }
                .onChange(of: sessions.count) { _ in
                    syncSelectionAndCache()
                }
        }
    }

    @ViewBuilder
    private var chatContentWithCompanion: some View {
        GeometryReader { geometry in
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
            .coordinateSpace(name: companionCoordinateSpace)
            .onAppear {
                if !didLoadWidths {
                    leftPanelWidth = leftPanelWidthStored
                    rightPanelWidth = rightPanelWidthStored
                    clampPanelWidths(containerWidth: geometry.size.width)
                    didLoadWidths = true
                }
            }
            .onChange(of: geometry.size.width) { newWidth in
                clampPanelWidths(containerWidth: newWidth)
            }
            .onChange(of: leftPanelType) { _ in
                clampPanelWidths(containerWidth: geometry.size.width)
            }
            .onChange(of: rightPanelType) { _ in
                clampPanelWidths(containerWidth: geometry.size.width)
            }
        }
    }

    private var chatSessionsStack: some View {
        ZStack {
            ForEach(cachedSessions) { session in
                let isSelected = selectedSessionId == session.id
                ChatSessionView(
                    worktree: worktree,
                    session: session,
                    sessionManager: sessionManager,
                    viewContext: viewContext,
                    isSelected: isSelected,
                    isCompanionResizing: isResizingCompanion
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(isSelected ? 1 : 0)
                .allowsHitTesting(isSelected)
                .zIndex(isSelected ? 1 : 0)
            }
        }
    }

    private var cachedSessions: [ChatSession] {
        if cachedSessionIds.isEmpty {
            let fallbackId = selectedSessionId ?? sessions.last?.id
            if let fallbackId,
               let fallback = sessions.first(where: { $0.id == fallbackId }) {
                return [fallback]
            }
            if let last = sessions.last {
                return [last]
            }
        }
        return cachedSessionIds.compactMap { id in
            sessions.first(where: { $0.id == id })
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

    private func maxLeftWidth(containerWidth: CGFloat, rightWidth: CGFloat) -> CGFloat {
        let rightTotal = rightPanel == nil ? 0 : rightWidth + dividerWidth
        let available = containerWidth - minCenterWidth - rightTotal - dividerWidth
        let ratioMax = containerWidth * maxPanelWidthRatio
        return max(minPanelWidth, min(available, ratioMax))
    }

    private func maxRightWidth(containerWidth: CGFloat, leftWidth: CGFloat) -> CGFloat {
        let leftTotal = leftPanel == nil ? 0 : leftWidth + dividerWidth
        let available = containerWidth - minCenterWidth - leftTotal - dividerWidth
        let ratioMax = containerWidth * maxPanelWidthRatio
        return max(minPanelWidth, min(available, ratioMax))
    }

    private func clampPanelWidths(containerWidth: CGFloat) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if leftPanel != nil {
                let maxWidth = maxLeftWidth(containerWidth: containerWidth, rightWidth: CGFloat(rightPanelWidth))
                let clamped = min(max(CGFloat(leftPanelWidth), minPanelWidth), maxWidth)
                if clamped != CGFloat(leftPanelWidth) {
                    leftPanelWidth = Double(clamped)
                }
            }
            if rightPanel != nil {
                let maxWidth = maxRightWidth(containerWidth: containerWidth, leftWidth: CGFloat(leftPanelWidth))
                let clamped = min(max(CGFloat(rightPanelWidth), minPanelWidth), maxWidth)
                if clamped != CGFloat(rightPanelWidth) {
                    rightPanelWidth = Double(clamped)
                }
            }
            if leftPanel != nil {
                let maxWidth = maxLeftWidth(containerWidth: containerWidth, rightWidth: CGFloat(rightPanelWidth))
                let clamped = min(max(CGFloat(leftPanelWidth), minPanelWidth), maxWidth)
                if clamped != CGFloat(leftPanelWidth) {
                    leftPanelWidth = Double(clamped)
                }
            }
        }
    }

    private var chatEmptyState: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "message.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.secondary)

                VStack(spacing: 8) {
                    Text("chat.noChatSessions", bundle: .main)
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("chat.startConversation", bundle: .main)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }

            // Responsive layout: row if <=5 agents, column if >5
            if enabledAgents.count <= 5 {
                HStack(spacing: 12) {
                    ForEach(enabledAgents, id: \.id) { agentMetadata in
                        agentButton(for: agentMetadata)
                    }
                }
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(100), spacing: 12), count: 3), spacing: 12) {
                    ForEach(enabledAgents, id: \.id) { agentMetadata in
                        agentButton(for: agentMetadata)
                    }
                }
                .padding(.horizontal, 20)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            loadEnabledAgents()
        }
        .onReceive(NotificationCenter.default.publisher(for: .agentMetadataDidChange)) { _ in
            loadEnabledAgents()
        }
    }

    @ViewBuilder
    private func agentButton(for agentMetadata: AgentMetadata) -> some View {
        Button {
            createNewSession(withAgent: agentMetadata.id)
        } label: {
            VStack(spacing: 8) {
                AgentIconView(metadata: agentMetadata, size: 12)
                Text(agentMetadata.name)
                    .font(.system(size: 13, weight: .medium))
            }
            .frame(width: 100, height: 80)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.separator.opacity(0.3), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func loadEnabledAgents() {
        Task {
            enabledAgents = AgentRegistry.shared.getEnabledAgents()
        }
    }

    private func createNewSession(withAgent agent: String) {
        guard let context = worktree.managedObjectContext else { return }

        let session = ChatSession(context: context)
        session.id = UUID()
        session.agentName = agent
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
