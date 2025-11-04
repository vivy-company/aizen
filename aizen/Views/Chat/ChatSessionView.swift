//
//  ChatSessionView.swift
//  aizen
//
//  Chat session interface with messages and input
//

import SwiftUI
import CoreData
import Combine
import Markdown

struct ChatSessionView: View {
    let worktree: Worktree
    @ObservedObject var session: ChatSession
    let sessionManager: ChatSessionManager

    @Environment(\.managedObjectContext) private var viewContext

    @StateObject private var agentRouter = AgentRouter()
    @StateObject private var audioService = AudioService()

    @State private var inputText = ""
    @State private var messages: [MessageItem] = []
    @State private var toolCalls: [ToolCall] = []
    @State private var isProcessing = false
    @State private var scrollProxy: ScrollViewProxy?
    @State private var currentAgentSession: AgentSession?
    @State private var showingPermissionAlert: Bool = false
    @State private var currentPermissionRequest: RequestPermissionRequest?
    @State private var cancellables = Set<AnyCancellable>()

    @State private var attachments: [URL] = []
    @State private var showingAttachmentPicker = false
    @State private var showingAuthSheet = false
    @State private var showingAgentPlan = false
    @State private var showingCommandAutocomplete = false
    @State private var commandSuggestions: [AvailableCommand] = []
    @State private var showingAgentSwitchWarning = false
    @State private var pendingAgentSwitch: String?
    @State private var showingVoiceRecording = false
    @State private var showingPermissionError = false
    @State private var permissionErrorMessage = ""
    @State private var showingAgentSetupDialog = false
    @State private var timelineItems: [TimelineItem] = []

    var selectedAgent: String {
        session.agentName ?? "claude"
    }

    private func rebuildTimeline() {
        timelineItems = (messages.map { .message($0) } + toolCalls.map { .toolCall($0) })
            .sorted { $0.timestamp < $1.timestamp }
    }

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    messageListView

                    Spacer(minLength: 0)

                    VStack(spacing: 8) {
                        if let agentSession = currentAgentSession, showingPermissionAlert, let request = currentPermissionRequest {
                            HStack {
                                PermissionRequestView(session: agentSession, request: request)
                                    .transition(.opacity)
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                        }

                        if !attachments.isEmpty {
                            attachmentChipsView
                                .padding(.horizontal, 20)
                        }

                        controlsBar
                            .padding(.horizontal, 20)

                        ChatInputBar(
                            inputText: $inputText,
                            attachments: $attachments,
                            isProcessing: $isProcessing,
                            showingVoiceRecording: $showingVoiceRecording,
                            showingAttachmentPicker: $showingAttachmentPicker,
                            showingCommandAutocomplete: $showingCommandAutocomplete,
                            showingPermissionError: $showingPermissionError,
                            permissionErrorMessage: $permissionErrorMessage,
                            commandSuggestions: commandSuggestions,
                            session: currentAgentSession,
                            selectedAgent: selectedAgent,
                            isSessionReady: isSessionReady,
                            audioService: audioService,
                            onSend: sendMessage,
                            onCancel: { Task { await currentAgentSession?.cancelCurrentPrompt() } },
                            onCommandSelect: selectCommand
                        )
                        .padding(.horizontal, 20)
                    }
                    .padding(.vertical, 16)
                }

                if showingAgentPlan, let plan = currentAgentSession?.agentPlan {
                    AgentPlanSidebarView(plan: plan, isShowing: $showingAgentPlan)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .focusedSceneValue(\.chatActions, ChatActions(cycleModeForward: cycleModeForward))
        .onAppear {
            setupAgentSession()
        }
        .onChange(of: selectedAgent) { _ in
            setupAgentSession()
        }
        .onChange(of: inputText) { newText in
            updateCommandSuggestions(newText)
        }
        .sheet(isPresented: $showingAuthSheet) {
            if let agentSession = currentAgentSession {
                AuthenticationSheet(session: agentSession)
            }
        }
        .sheet(isPresented: $showingAgentSetupDialog) {
            if let agentSession = currentAgentSession {
                AgentSetupDialog(session: agentSession)
            }
        }
        .alert(String(localized: "chat.agent.switch.title"), isPresented: $showingAgentSwitchWarning) {
            Button(String(localized: "chat.button.cancel"), role: .cancel) {
                pendingAgentSwitch = nil
            }
            Button(String(localized: "chat.button.switch"), role: .destructive) {
                if let newAgent = pendingAgentSwitch {
                    performAgentSwitch(to: newAgent)
                }
            }
        } message: {
            Text("chat.agent.switch.message", bundle: .main)
        }
        .alert(String(localized: "chat.permission.title"), isPresented: $showingPermissionError) {
            Button(String(localized: "chat.permission.openSettings")) {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                    NSWorkspace.shared.open(url)
                }
            }
            Button(String(localized: "chat.button.cancel"), role: .cancel) {}
        } message: {
            Text(permissionErrorMessage)
        }
    }

    // MARK: - Subviews

    private var messageListView: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 16) {
                    ForEach(timelineItems, id: \.id) { item in
                        switch item {
                        case .message(let message):
                            MessageBubbleView(message: message, agentName: message.role == .agent ? selectedAgent : nil)
                                .id(message.id)
                                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        case .toolCall(let toolCall):
                            ToolCallView(toolCall: toolCall)
                                .transition(.opacity.combined(with: .move(edge: .leading)))
                        }
                    }

                    if isProcessing {
                        processingIndicator
                            .id("processing")
                            .transition(.opacity)
                    }
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 20)
            }
            .onAppear {
                scrollProxy = proxy
                loadMessages()
            }
        }
    }

    private var processingIndicator: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.7)
                .controlSize(.small)

            if let thought = currentAgentSession?.currentThought {
                Text(renderInlineMarkdown(thought))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .modifier(ShimmerEffect())
                    .transition(.opacity)
            } else {
                Text("chat.agent.thinking", bundle: .main)
                    .font(.callout)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                    .modifier(ShimmerEffect())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var attachmentChipsView: some View {
        HStack(spacing: 8) {
            ForEach(attachments, id: \.self) { attachment in
                AttachmentChipWithDelete(url: attachment) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        attachments.removeAll { $0 == attachment }
                    }
                }
            }
            Spacer()
        }
    }

    private var controlsBar: some View {
        HStack(spacing: 8) {
            AgentSelectorMenu(selectedAgent: selectedAgent, onAgentSelect: requestAgentSwitch)

            if let agentSession = currentAgentSession, !agentSession.availableModes.isEmpty {
                ModeSelectorView(session: agentSession)
            }

            Spacer()
        }
    }

    // MARK: - Business Logic

    private var isSessionReady: Bool {
        currentAgentSession?.isActive == true && currentAgentSession?.needsAuthentication == false
    }

    private func cycleModeForward() {
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

    private func requestAgentSwitch(to newAgent: String) {
        guard newAgent != selectedAgent else { return }
        pendingAgentSwitch = newAgent
        showingAgentSwitchWarning = true
    }

    private func performAgentSwitch(to newAgent: String) {
        session.agentName = newAgent
        let displayName = AgentRegistry.shared.getMetadata(for: newAgent)?.name ?? newAgent.capitalized
        session.title = displayName

        session.objectWillChange.send()
        worktree.objectWillChange.send()

        do {
            try viewContext.save()
        } catch {
            print("Failed to save agent switch: \(error)")
        }

        if let sessionId = session.id {
            sessionManager.removeAgentSession(for: sessionId)
        }
        currentAgentSession = nil
        messages = []

        setupAgentSession()
        pendingAgentSwitch = nil
    }

    private func setupAgentSession() {
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

    private func loadMessages() {
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

    private func sendMessage() {
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

    private func setupSessionObservers(session: AgentSession) {
        cancellables.removeAll()

        session.$messages
            .receive(on: DispatchQueue.main)
            .sink { newMessages in
                messages = newMessages
                rebuildTimeline()
                if let lastMessage = newMessages.last {
                    scrollProxy?.scrollTo(lastMessage.id, anchor: .bottom)
                }
            }
            .store(in: &cancellables)

        session.$toolCalls
            .receive(on: DispatchQueue.main)
            .sink { newToolCalls in
                toolCalls = newToolCalls
                rebuildTimeline()
                if let lastCall = newToolCalls.last {
                    scrollProxy?.scrollTo(lastCall.id, anchor: .bottom)
                } else if let lastMessage = messages.last {
                    scrollProxy?.scrollTo(lastMessage.id, anchor: .bottom)
                }
            }
            .store(in: &cancellables)

        session.$isActive
            .receive(on: DispatchQueue.main)
            .sink { isActive in
                if !isActive {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isProcessing = false
                    }
                }
            }
            .store(in: &cancellables)

        session.$needsAuthentication
            .receive(on: DispatchQueue.main)
            .sink { needsAuth in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    showingAuthSheet = needsAuth
                }
            }
            .store(in: &cancellables)

        session.$needsAgentSetup
            .receive(on: DispatchQueue.main)
            .sink { needsSetup in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    showingAgentSetupDialog = needsSetup
                }
            }
            .store(in: &cancellables)

        session.$agentPlan
            .receive(on: DispatchQueue.main)
            .sink { plan in
                if plan != nil {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        showingAgentPlan = true
                    }
                } else {
                    showingAgentPlan = false
                }
            }
            .store(in: &cancellables)

        session.permissionHandler.$showingPermissionAlert
            .receive(on: DispatchQueue.main)
            .sink { showing in
                showingPermissionAlert = showing
            }
            .store(in: &cancellables)

        session.permissionHandler.$permissionRequest
            .receive(on: DispatchQueue.main)
            .sink { request in
                currentPermissionRequest = request
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
            print("Failed to save message: \(error)")
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

    private func scrollToBottom() {
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

    private func renderInlineMarkdown(_ text: String) -> AttributedString {
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

    private func updateCommandSuggestions(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)

        if trimmed.hasPrefix("/") {
            let commandPart = String(trimmed.dropFirst()).lowercased()

            guard let agentSession = currentAgentSession else {
                showingCommandAutocomplete = false
                return
            }

            if commandPart.isEmpty {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                    commandSuggestions = agentSession.availableCommands
                    showingCommandAutocomplete = !commandSuggestions.isEmpty
                }
            } else {
                let filtered = agentSession.availableCommands.filter { command in
                    command.name.lowercased().hasPrefix(commandPart) ||
                    command.description.lowercased().contains(commandPart)
                }

                withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                    commandSuggestions = filtered
                    showingCommandAutocomplete = !filtered.isEmpty
                }
            }
        } else {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                showingCommandAutocomplete = false
                commandSuggestions = []
            }
        }
    }

    private func selectCommand(_ command: AvailableCommand) {
        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
            inputText = "/\(command.name) "
            showingCommandAutocomplete = false
        }
    }
}
