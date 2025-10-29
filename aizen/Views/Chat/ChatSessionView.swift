//
//  ChatSessionView.swift
//  aizen
//
//  Chat session interface with messages and input
//

import SwiftUI
import CoreData
import Combine
import UniformTypeIdentifiers
import Markdown

struct ChatSessionView: View {
    let worktree: Worktree
    @ObservedObject var session: ChatSession
    let sessionManager: ChatSessionManager

    @Environment(\.managedObjectContext) private var viewContext

    @StateObject private var agentRouter = AgentRouter()
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
    @State private var isHoveringInput = false
    @State private var showingAuthSheet = false
    @State private var showingAgentPlan = false
    @State private var showingCommandAutocomplete = false
    @State private var commandSuggestions: [AvailableCommand] = []
    @State private var showingAgentPicker = false
    @State private var showingAgentSwitchWarning = false
    @State private var pendingAgentSwitch: String?
    @State private var dashPhase: CGFloat = 0
    @State private var gradientRotation: Double = 0
    @StateObject private var audioService = AudioService()
    @State private var showingVoiceRecording = false
    @State private var showingPermissionError = false
    @State private var permissionErrorMessage = ""

    var selectedAgent: String {
        session.agentName ?? "claude"
    }

    var timelineItems: [TimelineItem] {
        var items: [TimelineItem] = []

        // Add messages
        for message in messages {
            items.append(.message(message))
        }

        // Add tool calls
        for toolCall in toolCalls {
            items.append(.toolCall(toolCall))
        }

        // Sort by timestamp
        return items.sorted { a, b in
            let aTime = a.timestamp
            let bTime = b.timestamp
            return aTime < bTime
        }
    }

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    ScrollViewReader { proxy in
                        ScrollView(showsIndicators: false) {
                            LazyVStack(spacing: 16) {
                                // Render messages and tool calls in chronological order
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

                    Spacer(minLength: 0)

                    VStack(spacing: 8) {
                        if let agentSession = currentAgentSession, showingPermissionAlert, let request = currentPermissionRequest {
                            HStack {
                                permissionButtonsView(session: agentSession, request: request)
                                    .transition(.opacity)
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                        }

                        if !attachments.isEmpty {
                            HStack(spacing: 8) {
                                ForEach(attachments, id: \.self) { attachment in
                                    attachmentChip(for: attachment)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                        }

                        HStack(spacing: 8) {
                            Menu {
                                ForEach(AgentRegistry.shared.availableAgents, id: \.self) { agent in
                                    Button {
                                        requestAgentSwitch(to: agent)
                                    } label: {
                                        HStack {
                                            AgentIconView(agent: agent, size: 14)
                                            Text(agent.capitalized)
                                            Spacer()
                                            if agent == selectedAgent {
                                                Image(systemName: "checkmark")
                                                    .foregroundStyle(.blue)
                                            }
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    AgentIconView(agent: selectedAgent, size: 12)
                                    Text(selectedAgent.capitalized)
                                        .font(.system(size: 11, weight: .medium))
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 8))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                            }
                            .menuStyle(.borderlessButton)
                            .buttonStyle(.plain)

                            if let agentSession = currentAgentSession, !agentSession.availableModes.isEmpty {
                                modeSelectorView
                            }

                            Spacer()
                        }
                        .padding(.horizontal, 20)

                        inputView
                            .padding(.horizontal, 20)
                    }
                    .padding(.vertical, 16)
                }

                if showingAgentPlan, let plan = currentAgentSession?.agentPlan {
                    agentPlanSidebar(plan: plan)
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
        session.title = newAgent.capitalized

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

        agentRouter.ensureSession(for: selectedAgent)
        if let newSession = agentRouter.getSession(for: selectedAgent) {
            sessionManager.setAgentSession(newSession, for: sessionId)
            currentAgentSession = newSession

            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                messages = newSession.messages
                toolCalls = newSession.toolCalls
            }

            setupSessionObservers(session: newSession)

            if !newSession.isActive {
                Task {
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
        }

        scrollToBottom()
    }

    private var inputView: some View {
        HStack(alignment: .center, spacing: 12) {
                if !showingVoiceRecording {
                    Button(action: { showingAttachmentPicker.toggle() }) {
                        Image(systemName: "paperclip")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(!isSessionReady ? .tertiary : .secondary)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!isSessionReady)
                    .transition(.opacity)
                }

                ZStack(alignment: .topLeading) {
                    if showingVoiceRecording {
                        VoiceRecordingView(
                            audioService: audioService,
                            onSend: { transcribedText in
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    showingVoiceRecording = false
                                    inputText = transcribedText
                                }
                            },
                            onCancel: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    showingVoiceRecording = false
                                }
                            }
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.opacity)
                    } else {
                        if inputText.isEmpty {
                            Text(isSessionReady ? String(localized: "chat.input.placeholder") : String(localized: "chat.session.starting"))
                                .font(.system(size: 14))
                                .foregroundStyle(.tertiary)
                                .padding(.top, 6)
                                .allowsHitTesting(false)
                        }

                        CustomTextEditor(
                            text: $inputText,
                            onSubmit: {
                                if !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    sendMessage()
                                }
                            }
                        )
                        .font(.system(size: 14))
                        .scrollContentBackground(.hidden)
                        .frame(height: textEditorHeight)
                        .disabled(!isSessionReady)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 40)

                if !showingVoiceRecording {
                    if let agentSession = currentAgentSession, !agentSession.availableModels.isEmpty {
                        Menu {
                            ForEach(agentSession.availableModels, id: \.modelId) { modelInfo in
                                Button {
                                    Task {
                                        try? await agentSession.setModel(modelInfo.modelId)
                                    }
                                } label: {
                                    HStack {
                                        Text(modelInfo.name)
                                        Spacer()
                                        if modelInfo.modelId == agentSession.currentModelId {
                                            Image(systemName: "checkmark")
                                                .foregroundStyle(.blue)
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                AgentIconView(agent: selectedAgent, size: 12)
                                if let currentModel = agentSession.availableModels.first(where: { $0.modelId == agentSession.currentModelId }) {
                                    Text(currentModel.name)
                                        .font(.system(size: 11, weight: .medium))
                                }
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                        }
                        .menuStyle(.borderlessButton)
                        .buttonStyle(.plain)
                        .help(String(localized: "chat.model.select"))
                        .transition(.opacity)
                    }

                    Button(action: {
                        Task {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                showingVoiceRecording = true
                            }
                            do {
                                try await audioService.startRecording()
                            } catch {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    showingVoiceRecording = false
                                }
                                if let recordingError = error as? AudioService.RecordingError {
                                    permissionErrorMessage = recordingError.localizedDescription + "\n\nPlease enable Microphone and Speech Recognition permissions in System Settings."
                                    showingPermissionError = true
                                }
                                print("Failed to start recording: \(error)")
                            }
                        }
                    }) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(!isSessionReady ? .tertiary : .secondary)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!isSessionReady)
                    .help(String(localized: "chat.voice.record"))
                    .transition(.opacity)

                    if isProcessing {
                        Button(action: {
                            Task {
                                await currentAgentSession?.cancelCurrentPrompt()
                            }
                        }) {
                            Image(systemName: "stop.circle.fill")
                                .font(.system(size: 22, weight: .medium))
                                .foregroundStyle(Color.red)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .transition(.opacity)
                    } else {
                        Button(action: sendMessage) {
                            Image(systemName: canSend ? "arrow.up.circle.fill" : "arrow.up.circle")
                                .font(.system(size: 22, weight: .medium))
                                .foregroundStyle(canSend ? Color.blue : Color.secondary.opacity(0.5))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSend)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: canSend)
                        .transition(.opacity)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: inputCornerRadius, style: .continuous))
            .overlay {
                if isProcessing && currentAgentSession?.currentThought != nil {
                    // Animated gradient border when thinking
                    RoundedRectangle(cornerRadius: inputCornerRadius, style: .continuous)
                        .strokeBorder(
                            AngularGradient(
                                colors: [.blue, .purple, .blue],
                                center: .center,
                                angle: .degrees(gradientRotation)
                            ),
                            lineWidth: 2
                        )
                } else if currentAgentSession?.currentModeId != "plan" {
                    RoundedRectangle(cornerRadius: inputCornerRadius, style: .continuous)
                        .strokeBorder(.separator.opacity(isHoveringInput ? 0.5 : 0.2), lineWidth: 0.5)
                }

                if currentAgentSession?.currentModeId == "plan" && !(isProcessing && currentAgentSession?.currentThought != nil) {
                    RoundedRectangle(cornerRadius: inputCornerRadius, style: .continuous)
                        .stroke(
                            AngularGradient(
                                colors: [.blue, .purple, .blue],
                                center: .center,
                                angle: .degrees(gradientRotation)
                            ),
                            style: StrokeStyle(lineWidth: 2, dash: [8])
                        )
                }
            }
            .onChange(of: isProcessing) { newValue in
                if newValue && currentAgentSession?.currentThought != nil {
                    startGradientAnimation()
                }
            }
            .onChange(of: currentAgentSession?.currentModeId) { newMode in
                if newMode == "plan" {
                    startGradientAnimation()
                }
            }
            .onAppear {
                if currentAgentSession?.currentModeId == "plan" {
                    startGradientAnimation()
                }
            }
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHoveringInput = hovering
                }
            }
            .overlay(alignment: .bottom) {
                if showingCommandAutocomplete && !commandSuggestions.isEmpty {
                    commandAutocompleteView
                        .offset(y: -60)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .fileImporter(
            isPresented: $showingAttachmentPicker,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    attachments.append(contentsOf: urls)
                }
            }
        }
    }

    private func attachmentChip(for url: URL) -> some View {
        AttachmentChipWithDelete(url: url) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                attachments.removeAll { $0 == url }
            }
        }
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isProcessing && isSessionReady
    }

    private var isSessionReady: Bool {
        currentAgentSession?.isActive == true && currentAgentSession?.needsAuthentication == false
    }

    private var inputCornerRadius: CGFloat {
        // More rounded when recording or single line
        if showingVoiceRecording {
            return 28
        }
        let lineCount = inputText.components(separatedBy: .newlines).count
        return lineCount > 1 ? 20 : 28
    }

    private var textEditorHeight: CGFloat {
        let lineCount = max(1, inputText.components(separatedBy: .newlines).count)
        let lineHeight: CGFloat = 18
        let baseHeight: CGFloat = lineHeight + 12
        return min(max(baseHeight, CGFloat(lineCount) * lineHeight + 12), 120)
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
        }

        Task.detached { @MainActor in
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

                DispatchQueue.main.async {
                    if let lastMessage = newMessages.last {
                        scrollProxy?.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
            .store(in: &cancellables)

        session.$toolCalls
            .receive(on: DispatchQueue.main)
            .sink { newToolCalls in
                toolCalls = newToolCalls

                DispatchQueue.main.async {
                    if let lastCall = newToolCalls.last {
                        scrollProxy?.scrollTo(lastCall.id, anchor: .bottom)
                    } else if let lastMessage = messages.last {
                        scrollProxy?.scrollTo(lastMessage.id, anchor: .bottom)
                    }
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

        session.$agentPlan
            .receive(on: DispatchQueue.main)
            .sink { plan in
                if let p = plan {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        showingAgentPlan = true
                    }
                } else {
                    showingAgentPlan = false
                }
            }
            .store(in: &cancellables)

        session.$showingPermissionAlert
            .receive(on: DispatchQueue.main)
            .sink { showing in
                showingPermissionAlert = showing
            }
            .store(in: &cancellables)

        session.$permissionRequest
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
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

        // Find all bold sections and keep only the last one
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
                // Found a bold section - replace the last one
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

    private func startGradientAnimation() {
        withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
            gradientRotation = 360
        }
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

    private var commandAutocompleteView: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(commandSuggestions.prefix(5), id: \.name) { command in
                Button {
                    selectCommand(command)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("/\(command.name)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary)

                        Text(command.description)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(Color.clear)

                if command.name != commandSuggestions.prefix(5).last?.name {
                    Divider()
                }
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.separator.opacity(0.3), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
        .padding(.horizontal, 12)
    }

    private func selectCommand(_ command: AvailableCommand) {
        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
            inputText = "/\(command.name) "
            showingCommandAutocomplete = false
        }
    }

    private func modeIcon(for mode: SessionMode) -> some View {
        Group {
            switch mode {
            case .chat:
                Image(systemName: "message")
            case .code:
                Image(systemName: "chevron.left.forwardslash.chevron.right")
            case .ask:
                Image(systemName: "questionmark.circle")
            }
        }
        .font(.system(size: 13))
    }

    private var modeSelectorView: some View {
        Menu {
            ForEach(currentAgentSession?.availableModes ?? [], id: \.id) { modeInfo in
                Button {
                    Task {
                        try? await currentAgentSession?.setModeById(modeInfo.id)
                    }
                } label: {
                    HStack {
                        if let mode = SessionMode(rawValue: modeInfo.id) {
                            modeIcon(for: mode)
                        }
                        Text(modeInfo.name)
                        Spacer()
                        if modeInfo.id == currentAgentSession?.currentModeId {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                if let currentModeId = currentAgentSession?.currentModeId,
                   let mode = SessionMode(rawValue: currentModeId) {
                    modeIcon(for: mode)
                }
                if let currentModeId = currentAgentSession?.currentModeId,
                   let currentMode = currentAgentSession?.availableModes.first(where: { $0.id == currentModeId }) {
                    Text(currentMode.name)
                        .font(.system(size: 12, weight: .medium))
                }

            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
    }

    private func buttonForeground(for option: PermissionOption) -> Color {
        if option.kind.contains("allow") {
            return .white
        } else if option.kind.contains("reject") {
            return .white
        } else {
            return .primary
        }
    }

    private func buttonBackground(for option: PermissionOption) -> Color {
        if option.kind == "allow_always" {
            return .green
        } else if option.kind.contains("allow") {
            return .blue
        } else if option.kind.contains("reject") {
            return .red
        } else {
            return .clear
        }
    }

    private func permissionButtonsView(session: AgentSession, request: RequestPermissionRequest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let toolCall = request.toolCall, let rawInput = toolCall.rawInput?.value as? [String: Any] {
                if let plan = rawInput["plan"] as? String {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("chat.plan.title", bundle: .main)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        PlanContentView(content: plan)
                            .font(.system(size: 12))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, minHeight: 200, maxHeight: 400, alignment: .leading)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    }
                } else if let filePath = rawInput["file_path"] as? String {
                    Text(String(format: String(localized: "chat.permission.write"), URL(fileURLWithPath: filePath).lastPathComponent))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else if let command = rawInput["command"] as? String {
                    Text(String(format: String(localized: "chat.permission.run"), command))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            HStack(spacing: 6) {

            if let options = request.options {
                ForEach(options, id: \.optionId) { option in
                    Button {
                        session.respondToPermission(optionId: option.optionId)
                    } label: {
                        HStack(spacing: 3) {
                            if option.kind.contains("allow") {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 10))
                            } else if option.kind.contains("reject") {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 10))
                            }
                            Text(option.name)
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(buttonForeground(for: option))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background {
                            buttonBackground(for: option)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func agentPlanSidebar(plan: Plan) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("chat.plan.sidebar.title", bundle: .main)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()

                Button { showingAgentPlan = false } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(plan.entries.enumerated()), id: \.offset) { index, entry in
                        HStack(alignment: .top, spacing: 12) {
                            Circle()
                                .fill(statusColor(for: entry.status))
                                .frame(width: 8, height: 8)
                                .padding(.top, 6)

                            VStack(alignment: .leading, spacing: 4) {
                                PlanContentView(content: entry.content)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.primary)

                                if let activeForm = entry.activeForm, entry.status == .inProgress {
                                    PlanContentView(content: activeForm)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                        .italic()
                                }

                                Text(statusLabel(for: entry.status))
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(statusColor(for: entry.status))
                                    .textCase(.uppercase)
                            }

                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(entry.status == .inProgress ? Color.blue.opacity(0.05) : Color.clear)
                        )

                        if index < plan.entries.count - 1 {
                            Divider()
                                .padding(.horizontal, 16)
                        }
                    }
                }
                .padding(.vertical, 12)
            }
        }
        .frame(width: 280)
        .background(.ultraThinMaterial)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(.separator)
                .frame(width: 1)
        }
    }

    private func statusColor(for status: PlanEntryStatus) -> Color {
        switch status {
        case .pending:
            return .secondary
        case .inProgress:
            return .blue
        case .completed:
            return .green
        case .cancelled:
            return .red
        }
    }

    private func statusLabel(for status: PlanEntryStatus) -> String {
        switch status {
        case .pending:
            return String(localized: "chat.status.pending")
        case .inProgress:
            return String(localized: "chat.status.inProgress")
        case .completed:
            return String(localized: "chat.status.completed")
        case .cancelled:
            return String(localized: "chat.status.cancelled")
        }
    }

}

// MARK: - Shimmer Effect

struct ShimmerEffect: ViewModifier {
    private let animation: Animation
    private let gradient: Gradient
    private let min: CGFloat
    private let max: CGFloat

    @State private var isInitialState = true
    @Environment(\.layoutDirection) private var layoutDirection

    init(
        animation: Animation = .linear(duration: 1.5).delay(0.25).repeatForever(autoreverses: false),
        gradient: Gradient = Gradient(colors: [
            .black.opacity(0.3),
            .black,
            .black.opacity(0.3)
        ]),
        bandSize: CGFloat = 0.3
    ) {
        self.animation = animation
        self.gradient = gradient
        self.min = 0 - bandSize
        self.max = 1 + bandSize
    }

    var startPoint: UnitPoint {
        if layoutDirection == .rightToLeft {
            isInitialState ? UnitPoint(x: max, y: min) : UnitPoint(x: 0, y: 1)
        } else {
            isInitialState ? UnitPoint(x: min, y: min) : UnitPoint(x: 1, y: 1)
        }
    }

    var endPoint: UnitPoint {
        if layoutDirection == .rightToLeft {
            isInitialState ? UnitPoint(x: 1, y: 0) : UnitPoint(x: min, y: max)
        } else {
            isInitialState ? UnitPoint(x: 0, y: 0) : UnitPoint(x: max, y: max)
        }
    }

    func body(content: Content) -> some View {
        content
            .mask(
                LinearGradient(
                    gradient: gradient,
                    startPoint: startPoint,
                    endPoint: endPoint
                )
            )
            .animation(animation, value: isInitialState)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now()) {
                    isInitialState = false
                }
            }
    }
}

// MARK: - Authentication Sheet

struct AuthenticationSheet: View {
    @ObservedObject var session: AgentSession
    @Environment(\.dismiss) private var dismiss
    @State private var selectedMethodId: String?
    @State private var isAuthenticating = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("chat.authentication.required", bundle: .main)
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !session.authMethods.isEmpty {
                        ForEach(session.authMethods, id: \.id) { method in
                            authMethodButton(for: method)
                        }
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "lock.shield")
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary)

                            Text("chat.authentication.needed", bundle: .main)
                                .font(.headline)
                                .foregroundStyle(.primary)

                            Text("chat.authentication.instructions", bundle: .main)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    }
                }
                .padding(24)
            }

            Divider()

            HStack(spacing: 12) {
                if isAuthenticating {
                    ProgressView()
                        .scaleEffect(0.8)
                        .controlSize(.small)
                    Text("chat.authentication.authenticating", bundle: .main)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(String(localized: "chat.authentication.skip")) {
                    Task {
                        isAuthenticating = true
                        do {
                            try await session.createSessionWithoutAuth()
                            await MainActor.run {
                                isAuthenticating = false
                                dismiss()
                            }
                        } catch {
                            await MainActor.run {
                                isAuthenticating = false
                                print("Skip auth failed: \(error)")
                            }
                        }
                    }
                }
                .buttonStyle(.borderless)
                .disabled(isAuthenticating)

                Button(String(localized: "chat.button.cancel")) {
                    dismiss()
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(width: 500, height: 400)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private func authMethodButton(for method: AuthMethod) -> some View {
        Button {
            selectedMethodId = method.id
            performAuthentication(methodId: method.id)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: selectedMethodId == method.id ? "checkmark.circle.fill" : "key.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(selectedMethodId == method.id ? .green : .blue)

                    Text(method.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)

                    Spacer()

                    Image(systemName: "arrow.right")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                if let description = method.description {
                    Text(description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if method.id == "claude-login" {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("chat.authentication.notImplemented", bundle: .main)
                            .font(.caption)
                            .foregroundStyle(.orange)

                        Text("chat.authentication.terminalInstructions", bundle: .main)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            Text("claude /login")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.black.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))

                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString("claude /login", forType: .string)
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }

                        Text("chat.authentication.skipInstructions", bundle: .main)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(16)
            .background(.quaternary.opacity(selectedMethodId == method.id ? 0.8 : 0.3), in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(selectedMethodId == method.id ? Color.blue : Color.clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
        .disabled(isAuthenticating)
    }

    private func performAuthentication(methodId: String) {
        isAuthenticating = true

        Task {
            do {
                try await session.authenticate(authMethodId: methodId)
                await MainActor.run {
                    isAuthenticating = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isAuthenticating = false
                    print("Authentication failed: \(error)")
                }
            }
        }
    }
}

// MARK: - Tool Details Sheet

struct ToolDetailsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let toolCalls: [ToolCall]
    @State private var expandedTools: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("chat.tool.details.title", bundle: .main)
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(toolCalls) { toolCall in
                        toolCallDetailView(toolCall)
                    }
                }
                .padding(16)
            }
        }
        .background(.ultraThinMaterial)
        .frame(width: 650, height: 550)
    }

    @ViewBuilder
    private func toolCallDetailView(_ toolCall: ToolCall) -> some View {
        let isExpanded = expandedTools.contains(toolCall.toolCallId)

        VStack(alignment: .leading, spacing: 0) {
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    if isExpanded {
                        expandedTools.remove(toolCall.toolCallId)
                    } else {
                        expandedTools.insert(toolCall.toolCallId)
                    }
                }
            }) {
                HStack(spacing: 10) {
                    // Status indicator
                    Circle()
                        .fill(statusColor(for: toolCall.status))
                        .frame(width: 6, height: 6)

                    // Title and status
                    VStack(alignment: .leading, spacing: 2) {
                        Text(toolCall.title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.primary)

                        Text(statusLabel(for: toolCall.status))
                            .font(.system(size: 10))
                            .foregroundStyle(statusColor(for: toolCall.status))
                    }

                    Spacer()

                    // Expand/collapse indicator
                    if !toolCall.content.isEmpty {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())

            // Expanded content
            if isExpanded && !toolCall.content.isEmpty {
                Divider()
                    .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(toolCall.content.enumerated()), id: \.offset) { _, block in
                        CompactContentBlockView(block: block)
                    }
                }
                .padding(10)
                .padding(.horizontal, 2)
            }
        }
        .background(Color(.controlBackgroundColor).opacity(0.2))
        .cornerRadius(6)
    }

    private func statusColor(for status: ToolStatus) -> Color {
        switch status {
        case .pending: return .yellow
        case .inProgress: return .blue
        case .completed: return .green
        case .failed: return .red
        }
    }

    private func statusLabel(for status: ToolStatus) -> String {
        switch status {
        case .pending: return String(localized: "chat.status.pending")
        case .inProgress: return String(localized: "chat.tool.status.running")
        case .completed: return String(localized: "chat.tool.status.done")
        case .failed: return String(localized: "chat.tool.status.failed")
        }
    }
}

// MARK: - Compact Content Block View

struct CompactContentBlockView: View {
    let block: ContentBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch block {
            case .text(let content):
                ScrollView([.horizontal, .vertical]) {
                    Text(content.text)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 200)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(4)

            case .image(let content):
                Text(String(localized: "chat.content.imageType \(content.mimeType)"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

            case .resource(let content):
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "chat.content.resourceUri \(content.resource.uri)"))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if let text = content.resource.text {
                        ScrollView([.horizontal, .vertical]) {
                            Text(text)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 150)
                        .padding(8)
                        .background(Color(nsColor: .textBackgroundColor))
                        .cornerRadius(4)
                    }
                }

            case .audio(let content):
                Text(String(localized: "chat.content.audioType \(content.mimeType)"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

            case .embeddedResource(let content):
                Text(String(localized: "chat.content.resourceUri \(content.uri)"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

            case .diff(let content):
                ScrollView([.horizontal, .vertical]) {
                    VStack(alignment: .leading, spacing: 0) {
                        if let path = content.path {
                            Text(String(localized: "chat.content.file \(path)"))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .padding(.bottom, 4)
                        }

                        let diffText = "--- \(content.path ?? "original")\n+++ \(content.path ?? "modified")\n\(content.oldText)\n\(content.newText)"
                        ForEach(diffText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init), id: \.self) { line in
                            Text(line)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(diffLineColor(for: line))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .textSelection(.enabled)
                }
                .frame(maxHeight: 200)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(4)

            case .terminalEmbed(let content):
                ScrollView([.horizontal, .vertical]) {
                    Text(content.output)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 200)
                .padding(8)
                .background(Color.black.opacity(0.8))
                .cornerRadius(4)
                .foregroundStyle(.white)
            }
        }
    }

    private func diffLineColor(for line: String) -> Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") {
            return .green
        } else if line.hasPrefix("-") && !line.hasPrefix("---") {
            return .red
        } else if line.hasPrefix("@@") {
            return .blue
        }
        return .primary
    }
}

// MARK: - Chat Actions for Keyboard Shortcuts

struct ChatActions {
    let cycleModeForward: () -> Void
}

private struct ChatActionsKey: FocusedValueKey {
    typealias Value = ChatActions
}

extension FocusedValues {
    var chatActions: ChatActions? {
        get { self[ChatActionsKey.self] }
        set { self[ChatActionsKey.self] = newValue }
    }
}

// MARK: - Plan Content View

struct PlanContentView: View {
    let content: String

    var body: some View {
        ScrollView {
            MarkdownRenderedView(content: content, isStreaming: false)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
    }
}

// MARK: - Timeline Item

enum TimelineItem {
    case message(MessageItem)
    case toolCall(ToolCall)

    var id: String {
        switch self {
        case .message(let msg):
            return msg.id
        case .toolCall(let tool):
            return tool.id
        }
    }

    var timestamp: Date {
        switch self {
        case .message(let msg):
            return msg.timestamp
        case .toolCall(let tool):
            return tool.timestamp
        }
    }
}
