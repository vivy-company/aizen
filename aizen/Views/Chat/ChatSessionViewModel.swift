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

    let messageHandler: MessageHandler
    private let agentSwitcher: AgentSwitcher
    private let commandHandler = CommandAutocompleteHandler()

    // MARK: - Services

    @Published var audioService = AudioService()

    // MARK: - State

    @Published var inputText = ""
    @Published var messages: [MessageItem] = []
    @Published var toolCalls: [ToolCall] = []
    @Published var isProcessing = false
    @Published var currentAgentSession: AgentSession?
    @Published var currentPermissionRequest: RequestPermissionRequest?
    @Published var attachments: [URL] = []
    @Published var commandSuggestions: [AvailableCommand] = []
    @Published var timelineItems: [TimelineItem] = []

    // MARK: - UI State Flags

    @Published var showingPermissionAlert: Bool = false
    @Published var showingAgentSwitchWarning = false
    @Published var pendingAgentSwitch: String?
    @Published var showingCommandAutocomplete: Bool = false

    // MARK: - Derived State (bridges nested AgentSession properties for reliable observation)
    @Published var needsAuth: Bool = false
    @Published var needsSetup: Bool = false
    @Published var needsUpdate: Bool = false
    @Published var versionInfo: AgentVersionInfo?
    @Published var currentAgentPlan: Plan?
    @Published var hasModes: Bool = false
    @Published var currentModeId: String?

    // MARK: - Internal State

    var scrollProxy: ScrollViewProxy?
    private var cancellables = Set<AnyCancellable>()
    private var notificationCancellables = Set<AnyCancellable>()
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
        currentAgentSession?.isActive == true && !needsAuth
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

        self.messageHandler = MessageHandler(viewContext: viewContext, session: session)
        self.agentSwitcher = AgentSwitcher(viewContext: viewContext, session: session)

        setupNotificationObservers()
        setupInputTextObserver()
    }

    // MARK: - Lifecycle

    func setupAgentSession() {
        guard let sessionId = session.id else { return }

        if let existingSession = sessionManager.getAgentSession(for: sessionId) {
            currentAgentSession = existingSession
            updateDerivedState(from: existingSession)
            setupSessionObservers(session: existingSession)

            if !existingSession.isActive {
                Task { [self] in
                    do {
                        try await existingSession.start(agentName: self.selectedAgent, workingDir: worktree.path!)
                    } catch {
                        self.logger.error("Failed to start session for \(self.selectedAgent): \(error.localizedDescription)")
                        // Session will show auth dialog or setup dialog automatically via needsAuthentication/needsAgentSetup
                    }
                }
            }
            return
        }

        Task {
            // Create a dedicated AgentSession for this chat session to avoid cross-tab interference
            let newSession = AgentSession(agentName: self.selectedAgent, workingDirectory: worktree.path ?? "")
            sessionManager.setAgentSession(newSession, for: sessionId)
            currentAgentSession = newSession
            updateDerivedState(from: newSession)

            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                messages = newSession.messages
                toolCalls = newSession.toolCalls
                rebuildTimeline()
            }

            setupSessionObservers(session: newSession)

            if !newSession.isActive {
                do {
                    try await newSession.start(agentName: self.selectedAgent, workingDir: worktree.path!)
                } catch {
                    self.logger.error("Failed to start new session for \(self.selectedAgent): \(error.localizedDescription)")
                    // Session will show auth dialog or setup dialog automatically via needsAuthentication/needsAgentSetup
                }
            }
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
        messages = []

        setupAgentSession()
        pendingAgentSwitch = nil
    }

    // MARK: - Command Autocomplete

    func updateCommandSuggestions(_ text: String) {
        commandSuggestions = commandHandler.updateCommandSuggestions(text, currentAgentSession: currentAgentSession)
    }

    func selectCommand(_ command: AvailableCommand) {
        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
            inputText = "/\(command.name) "
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
        $inputText
            .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { [weak self] newText in
                guard let self = self else { return }
                self.updateCommandSuggestions(newText)
            }
            .store(in: &notificationCancellables)

        $commandSuggestions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] suggestions in
                guard let self = self else { return }
                withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                    self.showingCommandAutocomplete = !suggestions.isEmpty
                }
            }
            .store(in: &notificationCancellables)
    }

    private func setupSessionObservers(session: AgentSession) {
        cancellables.removeAll()

        session.$messages
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newMessages in
                guard let self = self else { return }
                self.messages = newMessages
                self.rebuildTimeline()
                if let lastMessage = newMessages.last {
                    self.scrollProxy?.scrollTo(lastMessage.id, anchor: .bottom)
                }
            }
            .store(in: &cancellables)

        session.$toolCalls
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newToolCalls in
                guard let self = self else { return }
                self.toolCalls = newToolCalls
                self.rebuildTimeline()
                if let lastCall = newToolCalls.last {
                    self.scrollProxy?.scrollTo(lastCall.id, anchor: .bottom)
                } else if let lastMessage = self.messages.last {
                    self.scrollProxy?.scrollTo(lastMessage.id, anchor: .bottom)
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
                self?.logger.debug("Agent plan status changed: \(plan != nil)")
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
