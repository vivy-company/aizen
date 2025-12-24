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

    // MARK: - Handlers

    private let agentSwitcher: AgentSwitcher
    let autocompleteHandler = UnifiedAutocompleteHandler()

    // MARK: - Services

    @Published var audioService = AudioService()

    // MARK: - State

    @Published var inputText = ""
    @Published var pendingCursorPosition: Int?
    @Published var isProcessing = false
    @Published var currentAgentSession: AgentSession?
    @Published var currentPermissionRequest: RequestPermissionRequest?
    @Published var attachments: [ChatAttachment] = []
    @Published var timelineItems: [TimelineItem] = []

    // Track previous IDs for incremental sync (avoids storing full duplicate arrays)
    var previousMessageIds: Set<String> = []
    var previousToolCallIds: Set<String> = []

    // Historical messages loaded from Core Data (separate from live session)
    var historicalMessages: [MessageItem] = []

    /// Messages - combines historical + live session messages
    var messages: [MessageItem] {
        // If we have a live session, use its messages
        // Historical messages are only shown before session starts
        if let session = currentAgentSession, session.isActive {
            return session.messages
        }
        return historicalMessages
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

    var scrollProxy: ScrollViewProxy?
    @Published var isNearBottom: Bool = true
    private var cancellables = Set<AnyCancellable>()
    private var notificationCancellables = Set<AnyCancellable>()
    private var wasStreaming: Bool = false  // Track streaming state transitions
    let logger = Logger.forCategory("ChatSession")

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

        self.agentSwitcher = AgentSwitcher(viewContext: viewContext, session: session)

        setupNotificationObservers()
        setupInputTextObserver()
    }

    // MARK: - Lifecycle

    deinit {
        cancellables.removeAll()
        notificationCancellables.removeAll()
    }

    func setupAgentSession() {
        guard let sessionId = session.id else { return }

        // Check for pending input text or attachments (e.g., from review comments)
        prefillInputTextIfNeeded()
        loadPendingAttachmentsIfNeeded()

        // Configure autocomplete handler
        let worktreePath = worktree.path ?? ""
        autocompleteHandler.worktreePath = worktreePath

        if let existingSession = sessionManager.getAgentSession(for: sessionId) {
            currentAgentSession = existingSession
            autocompleteHandler.agentSession = existingSession
            updateDerivedState(from: existingSession)
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
                }
            } else {
                // Session already active, check for pending message
                Task {
                    await sendPendingMessageIfNeeded()
                }
            }
            return
        }

        guard !worktreePath.isEmpty else {
            logger.error("Chat session missing worktree path; cannot start agent session.")
            return
        }

        Task {
            // Create a dedicated AgentSession for this chat session to avoid cross-tab interference
            let newSession = AgentSession(agentName: self.selectedAgent, workingDirectory: worktreePath)
            sessionManager.setAgentSession(newSession, for: sessionId)
            currentAgentSession = newSession
            autocompleteHandler.agentSession = newSession
            updateDerivedState(from: newSession)

            // Index worktree files for autocomplete
            await autocompleteHandler.indexWorktree()

            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                // Reset previous IDs and rebuild timeline from new session
                previousMessageIds = Set(newSession.messages.map { $0.id })
                previousToolCallIds = Set(newSession.toolCalls.map { $0.id })
                rebuildTimeline()
            }

            setupSessionObservers(session: newSession)

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
        }
    }

    func persistDraftState() {
        guard let sessionId = session.id else { return }
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            sessionManager.setPendingInputText(inputText, for: sessionId)
        }
        if !attachments.isEmpty {
            sessionManager.setPendingAttachments(attachments, for: sessionId)
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

    private func prefillInputTextIfNeeded() {
        guard let sessionId = session.id,
              let pendingText = sessionManager.getDraftInputText(for: sessionId) else {
            return
        }

        // Prefill the input field so user can add context before sending
        inputText = pendingText
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

    // MARK: - Autocomplete

    func handleAutocompleteSelection() {
        guard let (replacement, range) = autocompleteHandler.selectCurrent() else { return }

        // Defer state changes to avoid "Publishing changes from within view updates" warning
        Task { @MainActor in
            let nsString = self.inputText as NSString
            self.inputText = nsString.replacingCharacters(in: range, with: replacement)

            // Set cursor position to end of inserted text
            self.pendingCursorPosition = range.location + replacement.count
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

    private func setupInputTextObserver() {
        // Persist draft text as user types (debounced to avoid excessive writes)
        $inputText
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] text in
                guard let self = self, let sessionId = self.session.id else { return }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    self.sessionManager.clearDraftInputText(for: sessionId)
                } else {
                    self.sessionManager.setPendingInputText(text, for: sessionId)
                }
            }
            .store(in: &cancellables)
    }

    private func setupSessionObservers(session: AgentSession) {
        cancellables.removeAll()

        session.$messages
            .throttle(for: .milliseconds(33), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] newMessages in
                guard let self = self else { return }
                // AgentSession is @MainActor so we're already on main thread
                // Direct call avoids coalescing of rapid streaming updates
                self.syncMessages(newMessages)

                // Only auto-scroll if user is near bottom
                if self.isNearBottom {
                    self.scrollToBottomDeferred()
                }
            }
            .store(in: &cancellables)

        // Observe toolCallsById changes (dictionary-based storage)
        session.$toolCallsById
            .receive(on: DispatchQueue.main)
            .throttle(for: .milliseconds(100), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in
                guard let self = self, let session = self.currentAgentSession else { return }
                let newToolCalls = session.toolCalls
                self.syncToolCalls(newToolCalls)
                // Only auto-scroll if user is near bottom
                if self.isNearBottom {
                    self.scrollToBottomDeferred()
                }
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
                guard let self = self else {
                    Logger.forCategory("ChatSession").error("Plan update received but self is nil!")
                    return
                }
                self.logger.info("Plan update received: \(plan?.entries.count ?? 0) entries, wasNil=\(self.currentAgentPlan == nil), isNil=\(plan == nil)")
                self.currentAgentPlan = plan
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

        // Observe isStreaming to update isProcessing - this is the source of truth
        session.$isStreaming
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isStreaming in
                guard let self = self else { return }
                self.isProcessing = isStreaming

                // Only rebuild when streaming actually ends (transitions from true to false)
                let streamingEnded = self.wasStreaming && !isStreaming
                self.wasStreaming = isStreaming

                if streamingEnded {
                    Task { @MainActor in
                        // Delay to ensure all tool calls are synced
                        try? await Task.sleep(for: .milliseconds(150))
                        withAnimation(.easeInOut(duration: 0.3)) {
                            self.rebuildTimelineWithGrouping(isStreaming: false)
                        }
                        self.previousMessageIds = Set(session.messages.map { $0.id })
                        self.previousToolCallIds = Set(session.toolCalls.map { $0.id })
                    }
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
