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

@MainActor
class ChatSessionViewModel: ObservableObject {
    // MARK: - Dependencies

    let worktree: Worktree
    let session: ChatSession
    let sessionManager: ChatSessionManager
    let viewContext: NSManagedObjectContext

    // MARK: - Services

    @Published var agentRouter = AgentRouter()
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

    // MARK: - Internal State

    var scrollProxy: ScrollViewProxy?
    private var cancellables = Set<AnyCancellable>()
    private let logger = Logger.forCategory("ChatSession")

    // MARK: - Computed Properties

    var selectedAgent: String {
        session.agentName ?? "claude"
    }

    var isSessionReady: Bool {
        currentAgentSession?.isActive == true && currentAgentSession?.needsAuthentication == false
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
    }

    // MARK: - Lifecycle

    func setupAgentSession() {
        guard let sessionId = session.id else { return }

        if let existingSession = sessionManager.getAgentSession(for: sessionId) {
            currentAgentSession = existingSession
            setupSessionObservers(session: existingSession)

            if !existingSession.isActive {
                Task {
                    try? await existingSession.start(agentName: selectedAgent, workingDir: worktree.path!)
                }
            }
            return
        }

        Task {
            await agentRouter.ensureSession(for: selectedAgent)
            if let newSession = agentRouter.getSession(for: selectedAgent) {
                sessionManager.setAgentSession(newSession, for: sessionId)
                currentAgentSession = newSession

                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    messages = newSession.messages
                    toolCalls = newSession.toolCalls
                    rebuildTimeline()
                }

                setupSessionObservers(session: newSession)

                if !newSession.isActive {
                    try? await newSession.start(agentName: selectedAgent, workingDir: worktree.path!)
                }
            }
        }
    }

    func loadMessages() {
        guard let messageSet = session.messages as? Set<ChatMessage> else {
            return
        }

        let sortedMessages = messageSet.sorted { $0.timestamp! < $1.timestamp! }

        let loadedMessages = sortedMessages.map { msg in
            MessageItem(
                id: msg.id!.uuidString,
                role: messageRoleFromString(msg.role!),
                content: msg.contentJSON!,
                timestamp: msg.timestamp!
            )
        }

        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            messages = loadedMessages
            rebuildTimeline()
        }

        scrollToBottom()
    }

    // MARK: - Message Operations

    func sendMessage() {
        let messageText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !messageText.isEmpty else { return }

        let messageAttachments = attachments

        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            inputText = ""
            attachments = []
            isProcessing = true
        }

        let userMessage = MessageItem(
            id: UUID().uuidString,
            role: .user,
            content: messageText,
            timestamp: Date()
        )

        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            messages.append(userMessage)
            rebuildTimeline()
        }

        Task {
            do {
                guard let agentSession = self.currentAgentSession else {
                    throw NSError(domain: "ChatSessionView", code: -1, userInfo: [NSLocalizedDescriptionKey: "No agent session"])
                }

                if !agentSession.isActive {
                    try await agentSession.start(agentName: self.selectedAgent, workingDir: self.worktree.path!)
                }

                try await agentSession.sendMessage(content: messageText, attachments: messageAttachments)

                self.saveMessage(content: messageText, role: "user", agentName: self.selectedAgent)
                self.scrollToBottom()
            } catch {
                let errorMessage = MessageItem(
                    id: UUID().uuidString,
                    role: .system,
                    content: String(localized: "chat.error.prefix \(error.localizedDescription)"),
                    timestamp: Date()
                )

                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    self.messages.append(errorMessage)
                    self.rebuildTimeline()
                }

                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    self.attachments = messageAttachments
                }
            }

            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                self.isProcessing = false
            }
        }
    }

    func cancelCurrentPrompt() {
        Task {
            await currentAgentSession?.cancelCurrentPrompt()
        }
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
        session.agentName = newAgent
        let displayName = AgentRegistry.shared.getMetadata(for: newAgent)?.name ?? newAgent.capitalized
        session.title = displayName

        session.objectWillChange.send()
        worktree.objectWillChange.send()

        do {
            try viewContext.save()
        } catch {
            logger.error("Failed to save agent switch: \(error.localizedDescription)")
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
        let trimmed = text.trimmingCharacters(in: .whitespaces)

        if trimmed.hasPrefix("/") {
            let commandPart = String(trimmed.dropFirst()).lowercased()

            guard let agentSession = currentAgentSession else {
                return
            }

            if commandPart.isEmpty {
                commandSuggestions = agentSession.availableCommands
            } else {
                let filtered = agentSession.availableCommands.filter { command in
                    command.name.lowercased().hasPrefix(commandPart) ||
                    command.description.lowercased().contains(commandPart)
                }
                commandSuggestions = filtered
            }
        } else {
            commandSuggestions = []
        }
    }

    func selectCommand(_ command: AvailableCommand) {
        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
            inputText = "/\(command.name) "
        }
    }

    // MARK: - Attachment Management

    func removeAttachment(_ attachment: URL) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            attachments.removeAll { $0 == attachment }
        }
    }

    // MARK: - Timeline

    func rebuildTimeline() {
        timelineItems = (messages.map { .message($0) } + toolCalls.map { .toolCall($0) })
            .sorted { $0.timestamp < $1.timestamp }
    }

    // MARK: - Scrolling

    func scrollToBottom() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            withAnimation(.easeOut(duration: 0.3)) {
                if let lastMessage = messages.last {
                    scrollProxy?.scrollTo(lastMessage.id, anchor: .bottom)
                } else if isProcessing {
                    scrollProxy?.scrollTo("processing", anchor: .bottom)
                }
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

        session.$needsAuthentication
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // Trigger view update - the View will check this property
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        session.$needsAgentSetup
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // Trigger view update - the View will check this property
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        session.$agentPlan
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // Trigger view update - the View will check this property
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        session.permissionHandler.$showingPermissionAlert
            .receive(on: DispatchQueue.main)
            .sink { [weak self] showing in
                self?.showingPermissionAlert = showing
            }
            .store(in: &cancellables)

        session.permissionHandler.$permissionRequest
            .receive(on: DispatchQueue.main)
            .sink { [weak self] request in
                self?.currentPermissionRequest = request
            }
            .store(in: &cancellables)
    }

    private func saveMessage(content: String, role: String, agentName: String) {
        let message = ChatMessage(context: viewContext)
        message.id = UUID()
        message.timestamp = Date()
        message.role = role
        message.agentName = agentName
        message.contentJSON = content
        message.session = session

        session.lastMessageAt = Date()

        do {
            try viewContext.save()
        } catch {
            logger.error("Failed to save message: \(error.localizedDescription)")
        }
    }

    private func messageRoleFromString(_ role: String) -> MessageRole {
        switch role.lowercased() {
        case "user":
            return .user
        case "agent":
            return .agent
        default:
            return .system
        }
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
