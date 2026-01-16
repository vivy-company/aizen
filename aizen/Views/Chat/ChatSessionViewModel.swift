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

    var messages: [MessageItem] {
        let source = currentAgentSession?.messages ?? historicalMessages
        
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
    private var notificationCancellables = Set<AnyCancellable>()
    private var wasStreaming: Bool = false
    private var observedSessionId: UUID?
    let logger = Logger.forCategory("ChatSession")
    var autoScrollTask: Task<Void, Never>?
    var suppressNextAutoScroll: Bool = false
    private var gitPauseApplied: Bool = false
    private var settingUpSessionId: UUID? = nil

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
        notificationCancellables.removeAll()
        observedSessionId = nil
    }
    
    private func loadHistoricalMessages() {
        guard let sessionId = session.id else {
            logger.warning("Cannot load historical messages: session has no ID")
            return
        }
        
        guard historicalMessages.isEmpty else { return }
        
        let fetchRequest: NSFetchRequest<ChatMessage> = ChatMessage.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "session.id == %@", sessionId as CVarArg)
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        fetchRequest.fetchLimit = 200
        
        do {
            let messages = try viewContext.fetch(fetchRequest)
            logger.info("Loaded \(messages.count) historical messages for session \(sessionId.uuidString)")
            
            self.historicalMessages = messages.reversed().compactMap { chatMessage in
                guard let id = chatMessage.id,
                      let role = chatMessage.role,
                      let contentJSON = chatMessage.contentJSON else {
                    logger.warning("Skipping message: missing required fields")
                    return nil
                }
                
                let messageRole: MessageRole
                switch role {
                case "user":
                    messageRole = .user
                case "agent", "assistant":
                    messageRole = .agent
                default:
                    logger.warning("Skipping message with unknown role: \(role)")
                    return nil
                }
                
                let contentBlocks = parseContentBlocks(from: contentJSON)
                let content = contentBlocks.map { block in
                    switch block {
                    case .text(let text):
                        return text.text
                    default:
                        return ""
                    }
                }.joined()
                
                return MessageItem(
                    id: id.uuidString,
                    role: messageRole,
                    content: content,
                    timestamp: chatMessage.timestamp ?? Date(),
                    contentBlocks: contentBlocks,
                    isComplete: true
                )
            }
            
            logger.info("Parsed \(self.historicalMessages.count) valid historical messages")
        } catch {
            logger.error("Failed to fetch historical messages: \(error.localizedDescription)")
        }
    }
    
    private func parseContentBlocks(from json: String) -> [ContentBlock] {
        guard let data = json.data(using: .utf8),
              let blocks = try? JSONDecoder().decode([ContentBlock].self, from: data) else {
            return [.text(TextContent(text: json))]
        }
        return blocks
    }

    func setupAgentSession() {
        guard let sessionId = session.id else { return }
        guard settingUpSessionId != sessionId else { return }
        settingUpSessionId = sessionId

        loadPendingAttachmentsIfNeeded()
        loadHistoricalMessages()

        let worktreePath = worktree.path ?? ""
        autocompleteHandler.worktreePath = worktreePath

        if let existingSession = sessionManager.getAgentSession(for: sessionId) {
            if existingSession.messages.isEmpty && !historicalMessages.isEmpty {
                existingSession.messages = historicalMessages
            }
            
            currentAgentSession = existingSession
            autocompleteHandler.agentSession = existingSession
            updateDerivedState(from: existingSession)

            previousMessageIds = Set(messages.map { $0.id })
            previousToolCallIds = Set(existingSession.toolCalls.map { $0.id })

            rebuildTimelineWithGrouping(isStreaming: existingSession.isStreaming)

            setupSessionObservers(session: existingSession)

            if !worktreePath.isEmpty {
                Task {
                    await autocompleteHandler.indexWorktree()
                }
            }

            if !existingSession.isActive {
                guard !worktreePath.isEmpty else {
                    logger.error("Chat session missing worktree path; cannot start agent session.")
                    settingUpSessionId = nil
                    return
                }
                Task { [self] in
                    defer { self.settingUpSessionId = nil }
                    do {
                        if let acpSessionId = await SessionPersistenceService.shared.getSessionId(
                            for: sessionId,
                            in: self.viewContext
                        ) {
                            self.logger.info("Resuming existing ACP session: \(acpSessionId)")
                            try await existingSession.resume(
                                acpSessionId: acpSessionId,
                                agentName: self.selectedAgent,
                                workingDir: worktreePath,
                                chatSessionId: sessionId
                            )
                        } else {
                            try await existingSession.start(
                                agentName: self.selectedAgent,
                                workingDir: worktreePath,
                                chatSessionId: sessionId
                            )
                        }
                        await sendPendingMessageIfNeeded()
                    } catch {
                        self.logger.error("Failed to start session for \(self.selectedAgent): \(error.localizedDescription)")
                    }
                }
            } else {
                Task {
                    defer { self.settingUpSessionId = nil }
                    await sendPendingMessageIfNeeded()
                }
            }
            return
        }

        guard !worktreePath.isEmpty else {
            logger.error("Chat session missing worktree path; cannot start agent session.")
            settingUpSessionId = nil
            return
        }

        let newSession = AgentSession(agentName: self.selectedAgent, workingDirectory: worktreePath)
        if !historicalMessages.isEmpty {
            newSession.messages = historicalMessages
        }
        
        let worktreeName = worktree.branch ?? "Chat"
        sessionManager.setAgentSession(newSession, for: sessionId, worktreeName: worktreeName)
        currentAgentSession = newSession
        autocompleteHandler.agentSession = newSession
        updateDerivedState(from: newSession)

        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            previousMessageIds = Set(messages.map { $0.id })
            previousToolCallIds = Set(newSession.toolCalls.map { $0.id })
            rebuildTimeline()
        }

        setupSessionObservers(session: newSession)

        Task {
            defer { self.settingUpSessionId = nil }
            await autocompleteHandler.indexWorktree()

            if !newSession.isActive {
                do {
                    if let acpSessionId = await SessionPersistenceService.shared.getSessionId(
                        for: sessionId,
                        in: self.viewContext
                    ) {
                        self.logger.info("Resuming existing ACP session: \(acpSessionId)")
                        try await newSession.resume(
                            acpSessionId: acpSessionId,
                            agentName: self.selectedAgent,
                            workingDir: worktreePath,
                            chatSessionId: sessionId
                        )
                    } else {
                        try await newSession.start(
                            agentName: self.selectedAgent,
                            workingDir: worktreePath,
                            chatSessionId: sessionId
                        )
                    }
                    await sendPendingMessageIfNeeded()
                } catch {
                    self.logger.error("Failed to start new session for \(self.selectedAgent): \(error.localizedDescription)")
                }
            } else {
                await sendPendingMessageIfNeeded()
            }
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
        
        let context = viewContext
        let newChatSession = ChatSession(context: context)
        newChatSession.id = UUID()
        newChatSession.agentName = selectedAgent
        newChatSession.createdAt = Date()
        newChatSession.worktree = worktree
        
        Task {
            let displayName = await AgentRegistry.shared.getMetadata(for: selectedAgent)?.name ?? selectedAgent.capitalized
            newChatSession.title = displayName
            
            do {
                try context.save()
                logger.info("Created new chat session: \(newChatSession.id?.uuidString ?? "unknown")")
                
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
                let freshAgentSession = AgentSession(agentName: selectedAgent, workingDirectory: worktreePath)
                sessionManager.setAgentSession(freshAgentSession, for: newChatSession.id!, worktreeName: worktree.branch)
                currentAgentSession = freshAgentSession
                autocompleteHandler.agentSession = freshAgentSession
                
                previousMessageIds = []
                previousToolCallIds = []
                timelineItems = []
                
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

    private func setupSessionObservers(session: AgentSession) {
        #if DEBUG
        logger.info("setupSessionObservers called")
        logger.info("  - session id: \(session.chatSessionId?.uuidString ?? "nil")")
        logger.info("  - currentAgentSession id: \(self.currentAgentSession?.chatSessionId?.uuidString ?? "nil")")
        logger.info("  - observedSessionId: \(self.observedSessionId?.uuidString ?? "nil")")
        logger.info("  - self.session.id: \(self.session.id?.uuidString ?? "nil")")
        logger.info("  - currentAgentSession === session: \(self.currentAgentSession === session)")
        logger.info("  - observedSessionId == self.session.id: \(self.observedSessionId == self.session.id)")
        logger.info("  - cancellables.isEmpty: \(self.cancellables.isEmpty)")
        logger.info("  - session.sessionState: \(String(describing: session.sessionState))")
        logger.info("  - session.isActive: \(session.isActive)")
        #endif
        
        // Only skip if we're ALREADY observing THIS EXACT session object for THIS ViewModel's ChatSession
        if currentAgentSession === session && 
           observedSessionId == self.session.id &&
           !cancellables.isEmpty {
            // Already observing - just sync latest state without rebuilding observers
            #if DEBUG
            logger.info("  -> SKIPPING observer rebuild, syncing state")
            #endif
            isProcessing = session.isStreaming
            updateDerivedState(from: session)
            #if DEBUG
            logger.info("  -> After sync: sessionState=\(String(describing: self.sessionState)), isSessionReady=\(self.isSessionReady)")
            #endif
            return
        }
        
        // Clear old observers and set up fresh ones
        #if DEBUG
        logger.info("  -> REBUILDING observers")
        #endif
        cancellables.removeAll()
        observedSessionId = self.session.id
        
        // Sync initial state
        isProcessing = session.isStreaming
        updateDerivedState(from: session)
        #if DEBUG
        logger.info("  -> After rebuild: sessionState=\(String(describing: self.sessionState)), isSessionReady=\(self.isSessionReady)")
        #endif

        session.$messages
            // Stream message updates as they arrive for smoother chunk rendering.
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newMessages in
                guard let self = self else { return }
                // AgentSession is @MainActor so we're already on main thread
                // Direct call avoids coalescing of rapid streaming updates
                self.syncMessages(newMessages)

                // Only auto-scroll if user is near bottom
                let shouldSkipAutoScroll = self.suppressNextAutoScroll
                self.suppressNextAutoScroll = false
                if self.isNearBottom && !shouldSkipAutoScroll {
                    self.scrollToBottomDeferred()
                }
            }
            .store(in: &cancellables)

        // Observe toolCallsById changes (dictionary-based storage)
        session.$toolCallsById
            .receive(on: DispatchQueue.main)
            .throttle(for: .milliseconds(60), scheduler: DispatchQueue.main, latest: true)
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

                if let path = self.worktree.path, !path.isEmpty {
                    if isStreaming && !self.gitPauseApplied {
                        self.gitPauseApplied = true
                        Task {
                            await GitIndexWatchCenter.shared.pause(worktreePath: path)
                        }
                    } else if !isStreaming && self.gitPauseApplied {
                        self.gitPauseApplied = false
                        Task {
                            await GitIndexWatchCenter.shared.resume(worktreePath: path)
                        }
                    }
                }

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
                        self.previousMessageIds = Set(self.messages.map { $0.id })
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
