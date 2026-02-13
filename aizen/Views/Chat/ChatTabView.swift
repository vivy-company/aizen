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
    let repositoryManager: RepositoryManager
    @Binding var selectedSessionId: UUID?
    @Binding var selectedTerminalSessionId: UUID?
    @Binding var selectedBrowserSessionId: UUID?

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.colorScheme) private var colorScheme
    private let sessionManager = ChatSessionManager.shared
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen", category: "ChatTabView")
    @State private var enabledAgents: [AgentMetadata] = []
    @State private var cachedSessionIds: [UUID] = []
    private let maxCachedSessions = 10
    private let recentSessionsLimit = 3
    private let recentSessionsFetchLimit = 50
    private let crossProjectRepositoryMarker = "__aizen.cross_project.workspace_repo__"

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
    @FetchRequest private var recentSessions: FetchedResults<ChatSession>

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

        let recentRequest: NSFetchRequest<ChatSession> = ChatSession.fetchRequest()
        if let repository = worktree.repository,
           (repository.isCrossProject || repository.note == crossProjectRepositoryMarker),
           let workspaceId = repository.workspace?.id {
            recentRequest.predicate = NSPredicate(
                format: "(worktree.repository.workspace.id == %@ OR worktree == nil) AND SUBQUERY(messages, $m, $m.role == 'user').@count > 0",
                workspaceId as CVarArg
            )
        } else if let worktreeId = worktree.id {
            recentRequest.predicate = NSPredicate(
                format: "(worktree.id == %@ OR worktree == nil) AND SUBQUERY(messages, $m, $m.role == 'user').@count > 0",
                worktreeId as CVarArg
            )
        } else {
            recentRequest.predicate = NSPredicate(value: false)
        }
        recentRequest.sortDescriptors = [NSSortDescriptor(key: "lastMessageAt", ascending: false)]
        recentRequest.fetchLimit = recentSessionsFetchLimit
        recentRequest.relationshipKeyPathsForPrefetching = ["worktree"]
        self._recentSessions = FetchRequest(fetchRequest: recentRequest, animation: nil)
    }

    var body: some View {
        if sessions.isEmpty {
            chatEmptyState
        } else {
            chatContentWithCompanion
                .onAppear {
                    syncSelectionAndCache()
                }
                .onChange(of: selectedSessionId) { _, _ in
                    updateCacheForSelection()
                }
                .onChange(of: sessions.count) { _, _ in
                    syncSelectionAndCache()
                }
        }
    }

    private var isCrossProjectScope: Bool {
        guard let repository = worktree.repository else { return false }
        return repository.isCrossProject || repository.note == crossProjectRepositoryMarker
    }

    private var scopedRecentSessions: [ChatSession] {
        let scopeStore = ChatSessionScopeStore.shared
        let workspaceId = isCrossProjectScope ? worktree.repository?.workspace?.id : nil
        let worktreeId = worktree.id
        let inScopeAttachedSessions = recentSessions.filter { session in
            guard let sessionWorktree = session.worktree, !sessionWorktree.isDeleted else {
                return false
            }

            if let workspaceId {
                return sessionWorktree.repository?.workspace?.id == workspaceId
            }
            guard let worktreeId else { return false }
            return sessionWorktree.id == worktreeId
        }

        let strictDetachedSessions = recentSessions.filter { session in
            guard session.worktree == nil else { return false }
            guard let sessionId = session.id else { return false }

            if let workspaceId {
                return scopeStore.workspaceId(for: sessionId) == workspaceId
            }
            if let worktreeId {
                return scopeStore.worktreeId(for: sessionId) == worktreeId
            }
            return false
        }

        let strictSessions = inScopeAttachedSessions + strictDetachedSessions
        if !strictSessions.isEmpty {
            return strictSessions
        }

        let fallbackDetachedSessions = recentSessions.filter { session in
            guard session.worktree == nil else { return false }
            guard let sessionId = session.id else { return false }

            if let workspaceId {
                if let storedWorkspaceId = scopeStore.workspaceId(for: sessionId) {
                    return storedWorkspaceId == workspaceId
                }
                return true
            }
            if let worktreeId {
                if let storedWorktreeId = scopeStore.worktreeId(for: sessionId) {
                    return storedWorktreeId == worktreeId
                }
                return true
            }
            return false
        }

        return inScopeAttachedSessions + fallbackDetachedSessions
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
            .onChange(of: geometry.size.width) { _, newWidth in
                // Defer to next run loop to break synchronous layout feedback cycle.
                // Writing @State during layout can re-trigger the same layout pass.
                DispatchQueue.main.async {
                    clampPanelWidths(containerWidth: newWidth)
                }
            }
            .onChange(of: leftPanelType) { _, _ in
                DispatchQueue.main.async {
                    clampPanelWidths(containerWidth: geometry.size.width)
                }
            }
            .onChange(of: rightPanelType) { _, _ in
                DispatchQueue.main.async {
                    clampPanelWidths(containerWidth: geometry.size.width)
                }
            }
        }
    }

    private func resolvedToolbarInset(from geometry: GeometryProxy) -> CGFloat {
        let safeInset = geometry.safeAreaInsets.top
        if safeInset > 0 {
            return safeInset
        }

        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            let estimatedInset = max(window.frame.height - window.contentLayoutRect.height, 0)
            if estimatedInset > 0 {
                return estimatedInset
            }
        }

        return 0
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
        guard containerWidth > 0 else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if leftPanel != nil {
                let maxWidth = maxLeftWidth(containerWidth: containerWidth, rightWidth: CGFloat(rightPanelWidth))
                let clamped = min(max(CGFloat(leftPanelWidth), minPanelWidth), maxWidth)
                if abs(clamped - CGFloat(leftPanelWidth)) > 0.5 {
                    leftPanelWidth = Double(clamped)
                }
            }
            if rightPanel != nil {
                let maxWidth = maxRightWidth(containerWidth: containerWidth, leftWidth: CGFloat(leftPanelWidth))
                let clamped = min(max(CGFloat(rightPanelWidth), minPanelWidth), maxWidth)
                if abs(clamped - CGFloat(rightPanelWidth)) > 0.5 {
                    rightPanelWidth = Double(clamped)
                }
            }
            if leftPanel != nil {
                let maxWidth = maxLeftWidth(containerWidth: containerWidth, rightWidth: CGFloat(rightPanelWidth))
                let clamped = min(max(CGFloat(leftPanelWidth), minPanelWidth), maxWidth)
                if abs(clamped - CGFloat(leftPanelWidth)) > 0.5 {
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
                HStack(spacing: 10) {
                    ForEach(enabledAgents, id: \.id) { agentMetadata in
                        agentButton(for: agentMetadata)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            } else {
                HStack {
                    Spacer(minLength: 0)
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 56, maximum: 64), spacing: 10)],
                        spacing: 10
                    ) {
                        ForEach(enabledAgents, id: \.id) { agentMetadata in
                            agentButton(for: agentMetadata)
                        }
                    }
                    .frame(maxWidth: 420)
                    Spacer(minLength: 0)
                }
            }

            if !scopedRecentSessions.isEmpty {
                resumeSessionSeparator
                recentSessionsSection
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

    private var resumeSessionSeparator: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .frame(height: 1)
            Text("Or resume a recent session")
                .font(.caption)
                .foregroundStyle(.secondary)
            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .frame(height: 1)
        }
        .frame(width: 420)
    }

    private var recentSessionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Recent Sessions")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Show more") {
                    SessionsWindowManager.shared.show(context: viewContext, worktreeId: worktree.id)
                }
                .buttonStyle(.link)
            }

            VStack(spacing: 8) {
                ForEach(Array(scopedRecentSessions.prefix(recentSessionsLimit)), id: \.objectID) { session in
                    Button {
                        resumeRecentSession(session)
                    } label: {
                        recentSessionRow(session)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: 420)
        .padding(.horizontal, 24)
    }

    @ViewBuilder
    private func agentButton(for agentMetadata: AgentMetadata) -> some View {
        Button {
            createNewSession(withAgent: agentMetadata.id)
        } label: {
            AgentIconView(metadata: agentMetadata, size: 14)
                .frame(width: 54, height: 54)
                .background {
                    emptyStateItemBackground(cornerRadius: 12)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(emptyStateItemStrokeColor, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private func loadEnabledAgents() {
        Task {
            enabledAgents = AgentRegistry.shared.getEnabledAgents()
        }
    }

    private func recentSessionRow(_ session: ChatSession) -> some View {
        let summary = sessionSummary(session)
        let agentName = sessionAgentLabel(session)
        let timestamp = relativeTimestamp(for: session)

        return HStack(spacing: 10) {
            AgentIconView(agent: session.agentName ?? "claude", size: 14)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(summary)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(agentName)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(timestamp)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            emptyStateItemBackground(cornerRadius: 10)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(emptyStateItemStrokeColor, lineWidth: 1)
        }
    }

    @ViewBuilder
    private func emptyStateItemBackground(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            shape
                .fill(.white.opacity(0.001))
                .glassEffect(.regular.interactive(), in: shape)
        } else {
            shape.fill(.thinMaterial)
        }
    }

    private var emptyStateItemStrokeColor: Color {
        colorScheme == .dark ? .white.opacity(0.10) : .black.opacity(0.08)
    }

    private func sessionSummary(_ session: ChatSession) -> String {
        guard let messages = session.messages as? Set<ChatMessage> else {
            return "Untitled Session"
        }

        let latestUser = messages
            .filter { $0.role == "user" }
            .sorted { (m1, m2) -> Bool in
                let t1 = m1.timestamp ?? Date.distantPast
                let t2 = m2.timestamp ?? Date.distantPast
                return t1 > t2
            }
            .first

        if let contentJSON = latestUser?.contentJSON,
           let contentData = contentJSON.data(using: .utf8),
           let contentBlocks = try? JSONDecoder().decode([ContentBlock].self, from: contentData) {
            var textParts: [String] = []
            for block in contentBlocks {
                if case .text(let textContent) = block {
                    textParts.append(textContent.text)
                }
            }
            let text = textParts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty {
                return "Empty message"
            }
            return truncate(text, limit: 80)
        }

        if let title = session.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return truncate(title, limit: 80)
        }

        return "Untitled Session"
    }

    private func sessionAgentLabel(_ session: ChatSession) -> String {
        let name = session.agentName ?? ""
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? SessionsListViewModel.unknownAgentLabel : trimmed
    }

    private func relativeTimestamp(for session: ChatSession) -> String {
        guard let lastMessage = session.lastMessageAt else {
            return "No messages"
        }
        return Self.recentTimestampFormatter.localizedString(for: lastMessage, relativeTo: Date())
    }

    private func truncate(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "..."
    }

    private func resumeRecentSession(_ session: ChatSession) {
        guard let sessionId = session.id else { return }

        if session.worktree == nil {
            session.worktree = worktree
            do {
                try viewContext.save()
                ChatSessionScopeStore.shared.clearScope(sessionId: sessionId)
                viewContext.refresh(session, mergeChanges: false)
            } catch {
                logger.error("Failed to reattach session: \(error.localizedDescription)")
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

    private static let recentTimestampFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

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
