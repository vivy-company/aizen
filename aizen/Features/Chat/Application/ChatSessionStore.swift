//
//  ChatSessionStore.swift
//  aizen
//
//  Business logic and state management for chat sessions
//

import ACP
import Combine
import CoreData
import Markdown
import os.log
import SwiftUI

// MARK: - Main Store
@MainActor
class ChatSessionStore: ObservableObject {
    // MARK: - Dependencies

    let worktree: Worktree
    let session: ChatSession
    let sessionManager: ChatSessionRegistry
    let viewContext: NSManagedObjectContext
    private let worktreePathSnapshot: String

    // MARK: - Handlers

    private let agentSwitcher: AgentSwitcher
    let autocompleteHandler = UnifiedAutocompleteHandler()

    // MARK: - Services

    @Published var audioService = AudioService()

    // MARK: - State

    @Published var isProcessing = false
    @Published var currentAgentSession: ChatAgentSession?
    @Published var currentPermissionRequest: RequestPermissionRequest?
    @Published var attachments: [ChatAttachment] = []
    @Published var timelineRenderEpoch: UInt64 = 0

    // Track previous IDs for incremental sync (avoids storing full duplicate arrays)
    var previousMessageIds: Set<String> = []
    var previousToolCallIds: Set<String> = []

    // Historical messages loaded from Core Data (separate from live session)
    var historicalMessages: [MessageItem] = []
    var historicalToolCalls: [ToolCall] = []

    var messages: [MessageItem] {
        let source = currentAgentSession?.messages ?? historicalMessages
        
        return source.filter { message in
            guard message.role == .agent else { return true }
            return !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// Tool calls - derives from ChatAgentSession (no duplicate storage)
    var toolCalls: [ToolCall] {
        currentAgentSession?.toolCalls ?? []
    }

    // MARK: - UI State Flags

    @Published var showingPermissionAlert: Bool = false
    @Published var showingAgentSwitchWarning = false
    @Published var pendingAgentSwitch: String?

    // MARK: - Derived State (bridges nested ChatAgentSession properties for reliable observation)
    @Published var needsAuth: Bool = false
    @Published var needsSetup: Bool = false
    @Published var needsUpdate: Bool = false
    @Published var versionInfo: AgentVersionInfo?
    @Published var currentAgentPlan: Plan?
    @Published var hasModes: Bool = false
    @Published var currentModeId: String?
    @Published var sessionState: SessionState = .idle
    @Published var isResumingSession: Bool = false

    // MARK: - Internal State

    @Published var scrollRequest: ScrollRequest?
    @Published var isNearBottom: Bool = true
    /// Tracks user intent: true when user has actively scrolled up away from bottom.
    /// Unlike isNearBottom (which flips on every content change), this only changes
    /// on explicit user scroll gestures or forced scroll-to-bottom actions.
    var userScrolledUp: Bool = false
    private var cancellables = Set<AnyCancellable>()
    private var notificationCancellables = Set<AnyCancellable>()
    private var wasStreaming: Bool = false
    private var observedSessionId: UUID?
    let logger = Logger.forCategory("ChatSession")
    var autoScrollTask: Task<Void, Never>?
    var suppressNextAutoScroll: Bool = false
    private var pendingStreamingRebuild: Bool = false
    private var pendingStreamingRebuildRequiresToolCallSync: Bool = false
    private var streamingRebuildTask: Task<Void, Never>?
    private var pendingNearBottomState: Bool?
    private var nearBottomStateTask: Task<Void, Never>?
    var draftPersistTask: Task<Void, Never>?
    private var skipNextMessagesEmission: Bool = false
    private var skipNextToolCallsEmission: Bool = false
    private var gitPauseApplied: Bool = false
    var settingUpSessionId: UUID? = nil

    // MARK: - Computed Properties

    /// Internal agent identifier used for ACP calls
    var selectedAgent: String {
        session.agentName ?? AgentRegistry.defaultAgentID
    }

    /// User-friendly agent name for UI (falls back to id)
    var selectedAgentDisplayName: String {
        if let meta = AgentRegistry.shared.getMetadata(for: selectedAgent) {
            return meta.name
        }
        return selectedAgent
    }

    var isSessionReady: Bool {
        sessionState.isReady && !needsAuth
    }

    var isSessionInitializing: Bool {
        sessionState.isInitializing
    }
    
    // Computed bindings for sheet presentation (prevents recreation on every render)
    var needsAuthBinding: Binding<Bool> {
        Binding(
            get: { self.needsAuth },
            set: { if !$0 { self.needsAuth = false } }
        )
    }
    
    var needsSetupBinding: Binding<Bool> {
        Binding(
            get: { self.needsSetup },
            set: { if !$0 { self.needsSetup = false } }
        )
    }
    
    var needsUpdateBinding: Binding<Bool> {
        Binding(
            get: { self.needsUpdate },
            set: { if !$0 { self.needsUpdate = false } }
        )
    }

    // MARK: - Initialization

    init(
        worktree: Worktree,
        session: ChatSession,
        sessionManager: ChatSessionRegistry,
        viewContext: NSManagedObjectContext
    ) {
        self.worktree = worktree
        self.session = session
        self.sessionManager = sessionManager
        self.viewContext = viewContext
        self.worktreePathSnapshot = worktree.path ?? ""

        self.agentSwitcher = AgentSwitcher(viewContext: viewContext, session: session)

        setupNotificationObservers()
    }

    // MARK: - Lifecycle

    deinit {
        nearBottomStateTask?.cancel()
        nearBottomStateTask = nil
        if gitPauseApplied, !worktreePathSnapshot.isEmpty {
            let path = worktreePathSnapshot
            Task { @MainActor in
                WorktreeRuntimeCoordinator.shared
                    .runtime(for: path)
                    .setGitRefreshSuspended(false)
            }
        }
        cancellables.removeAll()
        notificationCancellables.removeAll()
        observedSessionId = nil
    }

    /// Coalesce bottom-visibility updates to avoid state writes during SwiftUI layout transactions.
    func enqueueScrollPositionChange(_ isNearBottom: Bool, isLayoutResizing: Bool) {
        guard !isLayoutResizing else { return }

        if pendingNearBottomState == isNearBottom, nearBottomStateTask != nil {
            return
        }
        pendingNearBottomState = isNearBottom

        guard nearBottomStateTask == nil else { return }
        nearBottomStateTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            defer { self.nearBottomStateTask = nil }

            guard let nextState = self.pendingNearBottomState else { return }
            self.pendingNearBottomState = nil
            self.applyScrollPositionChange(nextState)
        }
    }

    private func applyScrollPositionChange(_ isNearBottom: Bool) {
        if self.isNearBottom != isNearBottom {
            self.isNearBottom = isNearBottom
        }
        // Mark userScrolledUp when user scrolls away from bottom.
        // Do NOT auto-clear it when near bottom — only cleared explicitly
        // by scrollToBottom() (button click or new turn start).
        if !isNearBottom && !userScrolledUp {
            userScrolledUp = true
        }
    }
    
    // MARK: - Derived State Updates
    func updateDerivedState(from session: ChatAgentSession) {
        needsAuth = session.needsAuthentication
        needsSetup = session.needsAgentSetup
        needsUpdate = session.needsUpdate
        versionInfo = session.versionInfo
        currentAgentPlan = session.agentPlan
        hasModes = !session.availableModes.isEmpty
        currentModeId = session.currentModeId
        sessionState = session.sessionState
        isResumingSession = session.isResumingSession
        showingPermissionAlert = session.permissionHandler.showingPermissionAlert
        currentPermissionRequest = session.permissionHandler.permissionRequest
    }

    // MARK: - Agent Management

    func cycleModeForward() {
        guard let session = currentAgentSession else { return }
        let modes = session.availableModes
        guard !modes.isEmpty else { return }

        if let currentIndex = modes.firstIndex(where: { $0.id == session.currentModeId }) {
            let nextIndex = (currentIndex + 1) % modes.count
            Task {
                try? await session.setModeById(modes[nextIndex].id)
            }
        }
    }

    func requestAgentSwitch(to newAgent: String) {
        guard newAgent != selectedAgent else { return }
        pendingAgentSwitch = newAgent
        showingAgentSwitchWarning = true
    }

    func performAgentSwitch(to newAgent: String) {
        agentSwitcher.performAgentSwitch(to: newAgent, worktree: worktree) {
            self.objectWillChange.send()
        }

        if let sessionId = session.id {
            sessionManager.removeAgentSession(for: sessionId)
        }
        currentAgentSession = nil
        // Clear tracked IDs and bump timeline revision (messages/toolCalls are computed from session)
        previousMessageIds = []
        previousToolCallIds = []
        timelineRenderEpoch &+= 1

        setupAgentSession()
        pendingAgentSwitch = nil
    }

    func restartSession() {
        guard let agentSession = currentAgentSession else { return }
        
        let context = viewContext
        let newChatSession = ChatSession(context: context)
        newChatSession.id = UUID()
        newChatSession.agentName = selectedAgent
        newChatSession.createdAt = Date()
        newChatSession.worktree = worktree
        
        Task {
            let displayName = AgentRegistry.shared.getMetadata(for: selectedAgent)?.name ?? selectedAgent.capitalized
            newChatSession.title = displayName
            
            do {
                try context.save()
                
                await agentSession.close()
                
                if let oldSessionId = session.id {
                    sessionManager.removeAgentSession(for: oldSessionId)
                }
                
                NotificationCenter.default.post(
                    name: .switchToChatSession,
                    object: nil,
                    userInfo: ["chatSessionId": newChatSession.id!]
                )
                
                let worktreePath = worktree.path ?? ""
                let freshAgentSession = ChatAgentSession(agentName: selectedAgent, workingDirectory: worktreePath)
                sessionManager.setAgentSession(freshAgentSession, for: newChatSession.id!, worktreeName: worktree.branch)
                currentAgentSession = freshAgentSession
                autocompleteHandler.agentSession = freshAgentSession
                
                previousMessageIds = []
                previousToolCallIds = []
                timelineRenderEpoch &+= 1
                
                setupSessionObservers(session: freshAgentSession)
                
                try await freshAgentSession.start(
                    agentName: selectedAgent,
                    workingDir: worktreePath,
                    chatSessionId: self.session.id
                )
            } catch {
                context.delete(newChatSession)
                do {
                    try context.save()
                } catch {
                    logger.error("Failed to rollback new session creation: \(error.localizedDescription)")
                }
                logger.error("Failed to create/start new session: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Markdown Rendering

    func renderInlineMarkdown(_ text: String) -> AttributedString {
        let document = Document(parsing: text)
        var lastBoldText: AttributedString?

        for child in document.children {
            if let paragraph = child as? Paragraph {
                if let bold = extractLastBold(paragraph.children) {
                    lastBoldText = bold
                }
            }
        }

        if let lastBold = lastBoldText {
            var result = lastBold
            result.font = .body.bold()
            return result
        }

        return AttributedString(text)
    }

    // MARK: - Private Helpers

    private func setupNotificationObservers() {
        NotificationCenter.default.publisher(for: .cycleModeShortcut)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.cycleModeForward()
            }
            .store(in: &notificationCancellables)

        NotificationCenter.default.publisher(for: .interruptAgentShortcut)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.cancelCurrentPrompt()
            }
            .store(in: &notificationCancellables)
    }

    func setupSessionObservers(session: ChatAgentSession) {
        // Only skip if we're ALREADY observing THIS EXACT session object for THIS ViewModel's ChatSession
        if currentAgentSession === session && 
           observedSessionId == self.session.id &&
           !cancellables.isEmpty {
            // Already observing - just sync latest state without rebuilding observers
            isProcessing = session.isStreaming
            updateDerivedState(from: session)
            return
        }
        
        // Clear old observers and set up fresh ones
        cancellables.removeAll()
        observedSessionId = self.session.id
        
        // Sync initial state
        isProcessing = session.isStreaming
        updateDerivedState(from: session)
        skipNextMessagesEmission = true
        skipNextToolCallsEmission = true

        session.$messages
            .removeDuplicates(by: Self.hasEquivalentMessageEnvelope)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newMessages in
                guard let self = self else { return }
                if self.skipNextMessagesEmission {
                    self.skipNextMessagesEmission = false
                    return
                }
                self.syncMessages(newMessages)
                self.suppressNextAutoScroll = false
            }
            .store(in: &cancellables)

        // Observe toolCallsById changes (dictionary-based storage)
        session.$toolCallsById
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self, let session = self.currentAgentSession else { return }
                if self.skipNextToolCallsEmission {
                    self.skipNextToolCallsEmission = false
                    return
                }
                let newToolCalls = session.toolCalls
                self.syncToolCalls(newToolCalls)
                self.performStreamingRebuildIfReady()
            }
            .store(in: &cancellables)

        session.$isActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isActive in
                guard let self = self else { return }
                if !isActive {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        self.isProcessing = false
                    }
                }
            }
            .store(in: &cancellables)

        // Direct observers for nested/derived state (fixes Issue 2)
        session.$needsAuthentication
            .receive(on: DispatchQueue.main)
            .sink { [weak self] needsAuth in
                self?.needsAuth = needsAuth
            }
            .store(in: &cancellables)

        session.$needsAgentSetup
            .receive(on: DispatchQueue.main)
            .sink { [weak self] needsSetup in
                self?.needsSetup = needsSetup
            }
            .store(in: &cancellables)

        session.$needsUpdate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] needsUpdate in
                self?.needsUpdate = needsUpdate
            }
            .store(in: &cancellables)

        session.$versionInfo
            .receive(on: DispatchQueue.main)
            .sink { [weak self] versionInfo in
                self?.versionInfo = versionInfo
            }
            .store(in: &cancellables)

        session.$agentPlan
            .receive(on: DispatchQueue.main)
            .sink { [weak self] plan in
                self?.currentAgentPlan = plan
            }
            .store(in: &cancellables)

        session.$availableModes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] modes in
                self?.hasModes = !modes.isEmpty
            }
            .store(in: &cancellables)

        session.$currentModeId
            .receive(on: DispatchQueue.main)
            .sink { [weak self] modeId in
                self?.currentModeId = modeId
            }
            .store(in: &cancellables)

        // Observe sessionState for lifecycle tracking
        session.$sessionState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.sessionState = state
            }
            .store(in: &cancellables)

        session.$isResumingSession
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isResuming in
                self?.isResumingSession = isResuming
            }
            .store(in: &cancellables)

        // Observe isStreaming to update isProcessing - this is the source of truth
        session.$isStreaming
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isStreaming in
                guard let self = self else { return }
                self.isProcessing = isStreaming

                if let path = self.worktree.path, !path.isEmpty {
                    if isStreaming && !self.gitPauseApplied {
                        self.gitPauseApplied = true
                        NotificationCenter.default.post(
                            name: .agentStreamingDidStart,
                            object: nil,
                            userInfo: ["worktreePath": path]
                        )
                        WorktreeRuntimeCoordinator.shared
                            .runtime(for: path)
                            .setGitRefreshSuspended(true)
                    } else if !isStreaming && self.gitPauseApplied {
                        self.gitPauseApplied = false
                        NotificationCenter.default.post(
                            name: .agentStreamingDidStop,
                            object: nil,
                            userInfo: ["worktreePath": path]
                        )
                        WorktreeRuntimeCoordinator.shared
                            .runtime(for: path)
                            .setGitRefreshSuspended(false)
                    }
                }

                // Only rebuild when streaming actually ends (transitions from true to false)
                let streamingEnded = self.wasStreaming && !isStreaming
                self.wasStreaming = isStreaming

                if streamingEnded {
                    if let lastAgent = session.messages.last(where: { $0.role == .agent }),
                       lastAgent.isComplete == false {
                        session.markLastMessageComplete()
                    }
                    let currentToolCallIds = Set(session.toolCalls.map { $0.id })
                    self.pendingStreamingRebuild = true
                    self.pendingStreamingRebuildRequiresToolCallSync = currentToolCallIds != self.previousToolCallIds
                    self.scheduleStreamingRebuild()
                }
            }
            .store(in: &cancellables)

        // Permission handler observers (enhanced for nested changes)
        session.permissionHandler.$showingPermissionAlert
            .receive(on: DispatchQueue.main)
            .sink { [weak self] showing in
                guard let self = self else { return }
                self.showingPermissionAlert = showing
            }
            .store(in: &cancellables)

        session.permissionHandler.$permissionRequest
            .receive(on: DispatchQueue.main)
            .sink { [weak self] request in
                guard let self = self else { return }
                self.currentPermissionRequest = request
            }
            .store(in: &cancellables)
    }

    /// Fast dedupe for streamed message arrays.
    /// Avoids deep `MessageItem` equality on every emission, which is expensive for long histories.
    private static func hasEquivalentMessageEnvelope(_ lhs: [MessageItem], _ rhs: [MessageItem]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        guard let left = lhs.last, let right = rhs.last else {
            return lhs.isEmpty && rhs.isEmpty
        }

        let leftTail = left.content.suffix(64)
        let rightTail = right.content.suffix(64)
        return left.id == right.id
            && left.isComplete == right.isComplete
            && left.content.count == right.content.count
            && leftTail == rightTail
            && left.contentBlocks.count == right.contentBlocks.count
    }

    func resetTimelineSyncState() {
        cancelPendingAutoScroll()
        scrollRequest = nil

        streamingRebuildTask?.cancel()
        streamingRebuildTask = nil
        pendingStreamingRebuild = false
        pendingStreamingRebuildRequiresToolCallSync = false

        skipNextMessagesEmission = false
        skipNextToolCallsEmission = false
    }

    func bootstrapTimelineState(from session: ChatAgentSession) {
        previousMessageIds = Set(messages.map { $0.id })
        previousToolCallIds = Set(session.toolCalls.map { $0.id })

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            rebuildTimelineWithGrouping(isStreaming: session.isStreaming)
        }
    }

    private func scheduleStreamingRebuild() {
        guard streamingRebuildTask == nil else { return }
        streamingRebuildTask = Task { @MainActor in
            defer { streamingRebuildTask = nil }
            try? await Task.sleep(for: .milliseconds(16))
            if Task.isCancelled {
                return
            }
            performStreamingRebuildIfReady()
        }
    }

    private func performStreamingRebuildIfReady() {
        guard pendingStreamingRebuild else { return }
        guard !(currentAgentSession?.isStreaming ?? false) else { return }
        if pendingStreamingRebuildRequiresToolCallSync {
            let currentToolCallIds = Set(currentAgentSession?.toolCalls.map { $0.id } ?? [])
            if currentToolCallIds != previousToolCallIds {
                return
            }
        }
        rebuildTimelineWithGrouping(isStreaming: false)
        previousMessageIds = Set(messages.map { $0.id })
        if let session = currentAgentSession {
            previousToolCallIds = Set(session.toolCalls.map { $0.id })
        }
        pendingStreamingRebuild = false
        pendingStreamingRebuildRequiresToolCallSync = false
    }

    private func extractLastBold(_ inlineElements: some Sequence<Markup>) -> AttributedString? {
        var lastBold: AttributedString?

        for element in inlineElements {
            if let strong = element as? Strong {
                lastBold = extractBoldContent(strong.children)
            }
        }

        return lastBold
    }

    private func extractBoldContent(_ inlineElements: some Sequence<Markup>) -> AttributedString {
        var result = AttributedString()

        for element in inlineElements {
            if let text = element as? Markdown.Text {
                result += AttributedString(text.string)
            } else if let strong = element as? Strong {
                result += extractBoldContent(strong.children)
            }
        }

        return result
    }
}
