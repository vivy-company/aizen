//
//  ChatSessionViewModel.swift
//  aizen
//
//  Business logic and state management for chat sessions
//

import SwiftUI
import CoreData
import Combine
import Markdown
import os.log

// MARK: - Main ViewModel
@MainActor
class ChatSessionViewModel: ObservableObject {
    // MARK: - Dependencies

    let worktree: Worktree
    let session: ChatSession
    let sessionManager: ChatSessionManager
    let viewContext: NSManagedObjectContext
    private let worktreePathSnapshot: String

    // MARK: - Handlers

    private let agentSwitcher: AgentSwitcher
    let autocompleteHandler = UnifiedAutocompleteHandler()

    // MARK: - Services

    @Published var audioService = AudioService()

    // MARK: - State

    @Published var isProcessing = false
    @Published var currentAgentSession: AgentSession?
    @Published var currentPermissionRequest: RequestPermissionRequest?
    @Published var attachments: [ChatAttachment] = []
    @Published var timelineItems: [TimelineItem] = []

    // Track previous IDs for incremental sync (avoids storing full duplicate arrays)
    var previousMessageIds: Set<String> = []
    var previousToolCallIds: Set<String> = []
    var childToolCallsByParentId: [String: [ToolCall]] = [:]

    // Historical messages loaded from Core Data (separate from live session)
    var historicalMessages: [MessageItem] = []

    /// Messages - combines historical + live session messages
    var messages: [MessageItem] {
        // If we have a live session, use its messages
        // Historical messages are only shown before session starts
        let source: [MessageItem]
        if let session = currentAgentSession, session.isActive {
            source = session.messages
        } else {
            source = historicalMessages
        }

        return source.filter { message in
            guard message.role == .agent else { return true }
            return !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// Tool calls - derives from AgentSession (no duplicate storage)
    var toolCalls: [ToolCall] {
        currentAgentSession?.toolCalls ?? []
    }

    // MARK: - UI State Flags

    @Published var showingPermissionAlert: Bool = false
    @Published var showingAgentSwitchWarning = false
    @Published var pendingAgentSwitch: String?

    // MARK: - Derived State (bridges nested AgentSession properties for reliable observation)
    @Published var needsAuth: Bool = false
    @Published var needsSetup: Bool = false
    @Published var needsUpdate: Bool = false
    @Published var versionInfo: AgentVersionInfo?
    @Published var currentAgentPlan: Plan?
    @Published var hasModes: Bool = false
    @Published var currentModeId: String?
    @Published var sessionState: SessionState = .idle

    // MARK: - Internal State

    @Published var scrollRequest: ScrollRequest?
    @Published var isNearBottom: Bool = true {
        didSet {
            if !isNearBottom {
                cancelPendingAutoScroll()
            }
        }
    }
    private var cancellables = Set<AnyCancellable>()
    private var notificationTasks: [Task<Void, Never>] = []
    private var sessionObserverTasks: [Task<Void, Never>] = []
    private var toolCallThrottleTask: Task<Void, Never>?
    private var wasStreaming: Bool = false  // Track streaming state transitions
    let logger = Logger.forCategory("ChatSession")
    var autoScrollTask: Task<Void, Never>?
    var suppressNextAutoScroll: Bool = false
    private var gitPauseApplied: Bool = false
    private var isSettingUpSession: Bool = false

    // MARK: - Computed Properties

    /// Internal agent identifier used for ACP calls
    var selectedAgent: String {
        session.agentName ?? "claude"
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
        sessionManager: ChatSessionManager,
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
        if gitPauseApplied, !worktreePathSnapshot.isEmpty {
            let path = worktreePathSnapshot
            Task {
                await GitIndexWatchCenter.shared.resume(worktreePath: path)
            }
        }
        cancellables.removeAll()
        notificationTasks.forEach { $0.cancel() }
        notificationTasks.removeAll()
        sessionObserverTasks.forEach { $0.cancel() }
        sessionObserverTasks.removeAll()
        toolCallThrottleTask?.cancel()
    }

    func setupAgentSession() {
        guard let sessionId = session.id else { return }
        guard !isSettingUpSession else { return }
        isSettingUpSession = true

        // Check for pending attachments (e.g., from review comments)
        loadPendingAttachmentsIfNeeded()

        // Configure autocomplete handler
        let worktreePath = worktree.path ?? ""
        autocompleteHandler.worktreePath = worktreePath

        if let existingSession = sessionManager.getAgentSession(for: sessionId) {
            currentAgentSession = existingSession
            autocompleteHandler.agentSession = existingSession
            updateDerivedState(from: existingSession)

            // Initialize sync state from existing session BEFORE setting up observers
            // This prevents all existing messages/tool calls from appearing as "new"
            previousMessageIds = Set(messages.map { $0.id })
            previousToolCallIds = Set(existingSession.toolCalls.map { $0.id })

            // Rebuild timeline with proper grouping for existing data
            rebuildTimelineWithGrouping(isStreaming: existingSession.isStreaming)

            setupSessionObservers(session: existingSession)

            // Index worktree files for autocomplete
            if !worktreePath.isEmpty {
                Task {
                    await autocompleteHandler.indexWorktree()
                }
            }

            if !existingSession.isActive {
                guard !worktreePath.isEmpty else {
                    logger.error("Chat session missing worktree path; cannot start agent session.")
                    isSettingUpSession = false
                    return
                }
                Task { [self] in
                    do {
                        try await existingSession.start(agentName: self.selectedAgent, workingDir: worktreePath)
                        await sendPendingMessageIfNeeded()
                    } catch {
                        self.logger.error("Failed to start session for \(self.selectedAgent): \(error.localizedDescription)")
                        // Session will show auth dialog or setup dialog automatically via needsAuthentication/needsAgentSetup
                    }
                    self.isSettingUpSession = false
                }
            } else {
                // Session already active, check for pending message
                Task {
                    await sendPendingMessageIfNeeded()
                    self.isSettingUpSession = false
                }
            }
            return
        }

        guard !worktreePath.isEmpty else {
            logger.error("Chat session missing worktree path; cannot start agent session.")
            isSettingUpSession = false
            return
        }

        // Create a dedicated AgentSession for this chat session to avoid cross-tab interference
        let newSession = AgentSession(agentName: self.selectedAgent, workingDirectory: worktreePath)
        let worktreeName = worktree.branch ?? "Chat"
        sessionManager.setAgentSession(newSession, for: sessionId, worktreeName: worktreeName)
        currentAgentSession = newSession
        autocompleteHandler.agentSession = newSession
        updateDerivedState(from: newSession)

        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            // Reset previous IDs and rebuild timeline from new session
            previousMessageIds = Set(messages.map { $0.id })
            previousToolCallIds = Set(newSession.toolCalls.map { $0.id })
            rebuildTimeline()
        }

        setupSessionObservers(session: newSession)

        Task {
            // Index worktree files for autocomplete
            await autocompleteHandler.indexWorktree()

            if !newSession.isActive {
                do {
                    try await newSession.start(agentName: self.selectedAgent, workingDir: worktreePath)
                    // Check for pending message after session starts
                    await sendPendingMessageIfNeeded()
                } catch {
                    self.logger.error("Failed to start new session for \(self.selectedAgent): \(error.localizedDescription)")
                    // Session will show auth dialog or setup dialog automatically via needsAuthentication/needsAgentSetup
                }
            } else {
                // Session already active, check for pending message
                await sendPendingMessageIfNeeded()
            }
            self.isSettingUpSession = false
        }
    }

    func persistDraftState(inputText: String) {
        guard let sessionId = session.id else { return }
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            sessionManager.setPendingInputText(inputText, for: sessionId)
        }
        if !attachments.isEmpty {
            sessionManager.setPendingAttachments(attachments, for: sessionId)
        }
    }

    func loadDraftInputText() -> String? {
        guard let sessionId = session.id else { return nil }
        return sessionManager.getDraftInputText(for: sessionId)
    }

    private var draftPersistTask: Task<Void, Never>?

    func debouncedPersistDraft(inputText: String) {
        draftPersistTask?.cancel()
        draftPersistTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            guard let sessionId = session.id else { return }
            let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                sessionManager.clearDraftInputText(for: sessionId)
            } else {
                sessionManager.setPendingInputText(inputText, for: sessionId)
            }
        }
    }

    private func sendPendingMessageIfNeeded() async {
        guard let sessionId = session.id,
              let pendingMessage = sessionManager.consumePendingMessage(for: sessionId),
              let agentSession = currentAgentSession else {
            return
        }

        do {
            try await agentSession.sendMessage(content: pendingMessage)
        } catch {
            logger.error("Failed to send pending message: \(error.localizedDescription)")
        }
    }

    private func loadPendingAttachmentsIfNeeded() {
        guard let sessionId = session.id,
              let pendingAttachments = sessionManager.consumePendingAttachments(for: sessionId) else {
            return
        }

        // Add pending attachments so user can add context before sending
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            attachments.append(contentsOf: pendingAttachments)
        }
    }

    // MARK: - Derived State Updates
    private func updateDerivedState(from session: AgentSession) {
        needsAuth = session.needsAuthentication
        needsSetup = session.needsAgentSetup
        needsUpdate = session.needsUpdate
        versionInfo = session.versionInfo
        currentAgentPlan = session.agentPlan
        hasModes = !session.availableModes.isEmpty
        currentModeId = session.currentModeId
        sessionState = session.sessionState
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
        // Clear tracked IDs and timeline (messages/toolCalls are computed from session)
        previousMessageIds = []
        previousToolCallIds = []
        timelineItems = []

        setupAgentSession()
        pendingAgentSwitch = nil
    }

    func restartSession() {
        guard let agentSession = currentAgentSession else { return }

        Task {
            // Close the current session
            await agentSession.close()

            // Clear messages and tool calls
            agentSession.messages.removeAll()
            agentSession.clearToolCalls()

            // Clear timeline
            previousMessageIds = []
            previousToolCallIds = []
            timelineItems = []

            // Restart the session
            let worktreePath = worktree.path ?? ""
            do {
                try await agentSession.start(agentName: selectedAgent, workingDir: worktreePath)
            } catch {
                logger.error("Failed to restart session: \(error.localizedDescription)")
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
        notificationTasks.append(Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .cycleModeShortcut) {
                guard !Task.isCancelled else { break }
                self?.cycleModeForward()
            }
        })

        notificationTasks.append(Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .interruptAgentShortcut) {
                guard !Task.isCancelled else { break }
                self?.cancelCurrentPrompt()
            }
        })
    }

    private func setupSessionObservers(session: AgentSession) {
        // Cancel existing observers
        cancellables.removeAll()
        sessionObserverTasks.forEach { $0.cancel() }
        sessionObserverTasks.removeAll()
        toolCallThrottleTask?.cancel()

        // Track previous messages for duplicate detection
        var previousMessages: [MessageItem] = []

        // Observe messages - stream updates as they arrive for smoother chunk rendering
        sessionObserverTasks.append(Task { [weak self] in
            for await newMessages in session.$messages.values {
                guard !Task.isCancelled, let self = self else { break }
                // Skip duplicate emissions
                guard newMessages != previousMessages else { continue }
                previousMessages = newMessages

                self.syncMessages(newMessages)

                // Only auto-scroll if user is near bottom
                let shouldSkipAutoScroll = self.suppressNextAutoScroll
                self.suppressNextAutoScroll = false
                if self.isNearBottom && !shouldSkipAutoScroll {
                    self.scrollToBottomDeferred()
                }
            }
        })

        // Observe toolCallsById changes with throttling (60ms)
        sessionObserverTasks.append(Task { [weak self] in
            for await _ in session.$toolCallsById.values {
                guard !Task.isCancelled, let self = self else { break }
                // Throttle by cancelling pending and scheduling new
                self.toolCallThrottleTask?.cancel()
                self.toolCallThrottleTask = Task {
                    try? await Task.sleep(for: .milliseconds(60))
                    guard !Task.isCancelled, let session = self.currentAgentSession else { return }
                    let newToolCalls = session.toolCalls
                    self.syncToolCalls(newToolCalls)
                    if self.isNearBottom {
                        self.scrollToBottomDeferred()
                    }
                }
            }
        })

        // Observe isActive
        sessionObserverTasks.append(Task { [weak self] in
            for await isActive in session.$isActive.values {
                guard !Task.isCancelled, let self = self else { break }
                if !isActive {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        self.isProcessing = false
                    }
                }
            }
        })

        // Direct observers for nested/derived state
        sessionObserverTasks.append(Task { [weak self] in
            for await needsAuth in session.$needsAuthentication.values {
                guard !Task.isCancelled else { break }
                self?.needsAuth = needsAuth
            }
        })

        sessionObserverTasks.append(Task { [weak self] in
            for await needsSetup in session.$needsAgentSetup.values {
                guard !Task.isCancelled else { break }
                self?.needsSetup = needsSetup
            }
        })

        sessionObserverTasks.append(Task { [weak self] in
            for await needsUpdate in session.$needsUpdate.values {
                guard !Task.isCancelled else { break }
                self?.needsUpdate = needsUpdate
            }
        })

        sessionObserverTasks.append(Task { [weak self] in
            for await versionInfo in session.$versionInfo.values {
                guard !Task.isCancelled else { break }
                self?.versionInfo = versionInfo
            }
        })

        sessionObserverTasks.append(Task { [weak self] in
            for await plan in session.$agentPlan.values {
                guard !Task.isCancelled, let self = self else { break }
                self.logger.info("Plan update received: \(plan?.entries.count ?? 0) entries, wasNil=\(self.currentAgentPlan == nil), isNil=\(plan == nil)")
                self.currentAgentPlan = plan
            }
        })

        sessionObserverTasks.append(Task { [weak self] in
            for await modes in session.$availableModes.values {
                guard !Task.isCancelled else { break }
                self?.hasModes = !modes.isEmpty
            }
        })

        sessionObserverTasks.append(Task { [weak self] in
            for await modeId in session.$currentModeId.values {
                guard !Task.isCancelled else { break }
                self?.currentModeId = modeId
            }
        })

        // Observe sessionState for lifecycle tracking
        sessionObserverTasks.append(Task { [weak self] in
            for await state in session.$sessionState.values {
                guard !Task.isCancelled else { break }
                self?.sessionState = state
            }
        })

        // Observe isStreaming to update isProcessing - this is the source of truth
        sessionObserverTasks.append(Task { [weak self] in
            for await isStreaming in session.$isStreaming.values {
                guard !Task.isCancelled, let self = self else { break }
                self.isProcessing = isStreaming

                if let path = self.worktree.path, !path.isEmpty {
                    if isStreaming && !self.gitPauseApplied {
                        self.gitPauseApplied = true
                        await GitIndexWatchCenter.shared.pause(worktreePath: path)
                    } else if !isStreaming && self.gitPauseApplied {
                        self.gitPauseApplied = false
                        await GitIndexWatchCenter.shared.resume(worktreePath: path)
                    }
                }

                // Only rebuild when streaming actually ends (transitions from true to false)
                let streamingEnded = self.wasStreaming && !isStreaming
                self.wasStreaming = isStreaming

                if streamingEnded {
                    // Delay to ensure all tool calls are synced
                    try? await Task.sleep(for: .milliseconds(150))
                    guard !Task.isCancelled else { break }
                    withAnimation(.easeInOut(duration: 0.3)) {
                        self.rebuildTimelineWithGrouping(isStreaming: false)
                    }
                    self.previousMessageIds = Set(self.messages.map { $0.id })
                    self.previousToolCallIds = Set(session.toolCalls.map { $0.id })
                }
            }
        })

        // Permission handler observers
        sessionObserverTasks.append(Task { [weak self] in
            for await showing in session.permissionHandler.$showingPermissionAlert.values {
                guard !Task.isCancelled else { break }
                self?.showingPermissionAlert = showing
            }
        })

        sessionObserverTasks.append(Task { [weak self] in
            for await request in session.permissionHandler.$permissionRequest.values {
                guard !Task.isCancelled else { break }
                self?.currentPermissionRequest = request
            }
        })
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
