//
//  ChatSessionView.swift
//  aizen
//
//  Chat session interface with messages and input
//

import SwiftUI
import CoreData

struct ChatSessionView: View {
    let worktree: Worktree
    @ObservedObject var session: ChatSession
    let sessionManager: ChatSessionManager
    let isSelected: Bool

    @Environment(\.managedObjectContext) private var viewContext

    @StateObject private var viewModel: ChatSessionViewModel

    // UI-only state
    @State private var showingAttachmentPicker = false
    @State private var showingVoiceRecording = false
    @State private var showingPermissionError = false
    @State private var permissionErrorMessage = ""
    @State private var showingUsageSheet = false
    @State private var selectedToolCall: ToolCall?
    @State private var fileToOpenInEditor: String?
    @State private var autocompleteWindow: AutocompleteWindowController?
    @State private var keyMonitor: Any?

    // Input state (local to avoid re-rendering entire view on keystroke)
    @State private var inputText = ""
    @State private var pendingCursorPosition: Int?

    private var supportsUsageMetrics: Bool {
        switch UsageProvider.fromAgentId(viewModel.selectedAgent) {
        case .codex, .claude, .gemini:
            return true
        default:
            return false
        }
    }

    init(
        worktree: Worktree,
        session: ChatSession,
        sessionManager: ChatSessionManager,
        viewContext: NSManagedObjectContext,
        isSelected: Bool
    ) {
        self.worktree = worktree
        self.session = session
        self.sessionManager = sessionManager
        self.isSelected = isSelected
        self._viewContext = Environment(\.managedObjectContext)

        let vm = ChatSessionViewModel(
            worktree: worktree,
            session: session,
            sessionManager: sessionManager,
            viewContext: viewContext
        )
        self._viewModel = StateObject(wrappedValue: vm)
    }

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ZStack(alignment: .bottomTrailing) {
                    ChatMessageList(
                        timelineItems: viewModel.timelineItems,
                        isProcessing: viewModel.isProcessing,
                        isSessionInitializing: viewModel.isSessionInitializing,
                        selectedAgent: viewModel.selectedAgent,
                        currentThought: viewModel.currentAgentSession?.currentThought,
                        currentIterationId: viewModel.currentAgentSession?.currentIterationId,
                        scrollRequest: viewModel.scrollRequest,
                        shouldAutoScroll: viewModel.isNearBottom,
                        onAppear: viewModel.loadMessages,
                        renderInlineMarkdown: viewModel.renderInlineMarkdown,
                        onToolTap: { toolCall in
                            selectedToolCall = toolCall
                        },
                        onOpenFileInEditor: { path in
                            fileToOpenInEditor = path
                        },
                        agentSession: viewModel.currentAgentSession,
                        onScrollPositionChange: { isNearBottom in
                            viewModel.isNearBottom = isNearBottom
                        },
                        childToolCallsProvider: { parentId in
                            viewModel.childToolCalls(for: parentId)
                        }
                    )

                    if shouldShowScrollToBottom {
                        Button(action: scrollToBottom) {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.primary)
                                .padding(10)
                                .background(.ultraThinMaterial, in: Circle())
                                .overlay(
                                    Circle()
                                        .strokeBorder(.separator.opacity(0.3), lineWidth: 0.5)
                                )
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 16)
                        .padding(.bottom, 16)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                }

                Spacer(minLength: 0)

                VStack(spacing: 8) {
                    // Permission Requests (excluding plan requests)
                    if let agentSession = viewModel.currentAgentSession,
                       viewModel.showingPermissionAlert,
                       let request = viewModel.currentPermissionRequest,
                       !isPlanRequest(request) {
                        HStack {
                            PermissionRequestView(session: agentSession, request: request)
                                .transition(.opacity)
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                    }

                    ChatControlsBar(
                        selectedAgent: viewModel.selectedAgent,
                        currentAgentSession: viewModel.currentAgentSession,
                        hasModes: viewModel.hasModes,
                        attachments: viewModel.attachments,
                        onRemoveAttachment: viewModel.removeAttachment,
                        plan: viewModel.currentAgentPlan,
                        onShowUsage: { showingUsageSheet = true },
                        onNewSession: viewModel.restartSession,
                        showsUsage: supportsUsageMetrics
                    )
                    .padding(.horizontal, 20)

                    ChatInputBar(
                        inputText: $inputText,
                        pendingCursorPosition: $pendingCursorPosition,
                        attachments: $viewModel.attachments,
                        isProcessing: $viewModel.isProcessing,
                        showingVoiceRecording: $showingVoiceRecording,
                        showingAttachmentPicker: $showingAttachmentPicker,
                        showingPermissionError: $showingPermissionError,
                        permissionErrorMessage: $permissionErrorMessage,
                        worktreePath: viewModel.worktree.path ?? "",
                        session: viewModel.currentAgentSession,
                        currentModeId: viewModel.currentModeId,
                        selectedAgent: viewModel.selectedAgent,
                        isSessionReady: viewModel.isSessionReady,
                        audioService: viewModel.audioService,
                        autocompleteHandler: viewModel.autocompleteHandler,
                        onSend: { sendMessage() },
                        onCancel: viewModel.cancelCurrentPrompt,
                        onAutocompleteSelect: { handleAutocompleteSelection() },
                        onImagePaste: { data, mimeType in
                            viewModel.attachments.append(.image(data, mimeType: mimeType))
                        },
                        onAgentSelect: viewModel.requestAgentSwitch
                    )
                    .padding(.horizontal, 20)
                }
                .padding(.top, 16)
                .padding(.bottom, 20)
            }
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .focusedSceneValue(\.chatActions, ChatActions(cycleModeForward: viewModel.cycleModeForward))
        .onAppear {
            // Load draft input text if available
            if let draft = viewModel.loadDraftInputText() {
                inputText = draft
            }
            if isSelected {
                viewModel.setupAgentSession()
                setupAutocompleteWindow()
                NotificationCenter.default.post(name: .chatViewDidAppear, object: nil)
                startKeyMonitorIfNeeded()
            }
        }
        .onDisappear {
            viewModel.persistDraftState(inputText: inputText)
            autocompleteWindow?.dismiss()
            NotificationCenter.default.post(name: .chatViewDidDisappear, object: nil)
            stopKeyMonitorIfNeeded()
            if showingVoiceRecording {
                viewModel.audioService.cancelRecording()
                showingVoiceRecording = false
            }
        }
        .onChange(of: isSelected) { _, selected in
            if selected {
                viewModel.setupAgentSession()
                setupAutocompleteWindow()
                NotificationCenter.default.post(name: .chatViewDidAppear, object: nil)
                startKeyMonitorIfNeeded()
            } else {
                autocompleteWindow?.dismiss()
                NotificationCenter.default.post(name: .chatViewDidDisappear, object: nil)
                stopKeyMonitorIfNeeded()
                if showingVoiceRecording {
                    viewModel.audioService.cancelRecording()
                    showingVoiceRecording = false
                }
            }
        }
        .onChange(of: inputText) { _, newText in
            viewModel.debouncedPersistDraft(inputText: newText)
        }
        .onReceive(viewModel.autocompleteHandler.$state) { state in
            updateAutocompleteWindow(state: state)
        }
        .onChange(of: fileToOpenInEditor) { _, path in
            guard let path = path else { return }
            NotificationCenter.default.post(
                name: .openFileInEditor,
                object: nil,
                userInfo: ["path": path]
            )
            fileToOpenInEditor = nil
        }
        .sheet(isPresented: viewModel.needsAuthBinding) {
            if let agentSession = viewModel.currentAgentSession {
                AuthenticationSheet(session: agentSession)
            }
        }
        .sheet(isPresented: viewModel.needsSetupBinding) {
            if let agentSession = viewModel.currentAgentSession {
                AgentSetupDialog(session: agentSession)
            }
        }
        .sheet(isPresented: viewModel.needsUpdateBinding) {
            if let versionInfo = viewModel.versionInfo {
                AgentUpdateSheet(
                    agentName: viewModel.selectedAgent,
                    versionInfo: versionInfo
                )
            }
        }
        .sheet(isPresented: $showingUsageSheet) {
            AgentUsageSheet(
                agentId: viewModel.selectedAgent,
                agentName: viewModel.selectedAgentDisplayName
            )
        }
        .sheet(item: $selectedToolCall) { toolCall in
            ToolDetailsSheet(toolCalls: [toolCall], agentSession: viewModel.currentAgentSession)
        }
        .sheet(isPresented: Binding(
            get: {
                // Show plan approval sheet if we have a plan request
                if viewModel.showingPermissionAlert,
                   let request = viewModel.currentPermissionRequest,
                   isPlanRequest(request) {
                    return true
                }
                return false
            },
            set: { if !$0 {
                viewModel.showingPermissionAlert = false
            }}
        )) {
            // Plan approval dialog
            if let request = viewModel.currentPermissionRequest,
               isPlanRequest(request),
               let agentSession = viewModel.currentAgentSession {
                PlanApprovalDialog(
                    session: agentSession,
                    request: request,
                    isPresented: Binding(
                        get: { true },
                        set: { if !$0 { viewModel.showingPermissionAlert = false } }
                    )
                )
            }
        }
        .alert(String(localized: "chat.agent.switch.title"), isPresented: $viewModel.showingAgentSwitchWarning) {
            Button(String(localized: "chat.button.cancel"), role: .cancel) {
                viewModel.pendingAgentSwitch = nil
            }
            Button(String(localized: "chat.button.switch"), role: .destructive) {
                if let newAgent = viewModel.pendingAgentSwitch {
                    viewModel.performAgentSwitch(to: newAgent)
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

    // MARK: - Helpers

    private func isPlanRequest(_ request: RequestPermissionRequest) -> Bool {
        guard let toolCall = request.toolCall,
              let rawInput = toolCall.rawInput?.value as? [String: Any],
              let _ = rawInput["plan"] as? String else {
            return false
        }
        return true
    }

    private var shouldShowScrollToBottom: Bool {
        !viewModel.isNearBottom && !viewModel.timelineItems.isEmpty
    }

    private func scrollToBottom() {
        viewModel.isNearBottom = true
        viewModel.scrollToBottom()
    }

    private func startKeyMonitorIfNeeded() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleVoiceShortcut(event)
        }
    }

    private func stopKeyMonitorIfNeeded() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    private func handleVoiceShortcut(_ event: NSEvent) -> NSEvent? {
        guard isSelected else { return event }

        let keyCodeEscape: UInt16 = 53
        let keyCodeReturn: UInt16 = 36
        let keyCodeC: UInt16 = 8

        if showingVoiceRecording {
            if event.keyCode == keyCodeEscape {
                cancelChatVoiceRecording()
                return nil
            }
            if event.keyCode == keyCodeReturn {
                acceptChatVoiceRecording()
                return nil
            }
        }

        // Ctrl+C clears input text (terminal-like behavior)
        if event.modifierFlags.contains(.control),
           event.keyCode == keyCodeC {
            if !inputText.isEmpty {
                inputText = ""
                return nil
            }
        }

        // Escape interrupts agent when processing, otherwise clears input
        if event.keyCode == keyCodeEscape && !showingVoiceRecording {
            if viewModel.isProcessing {
                viewModel.cancelCurrentPrompt()
                return nil
            } else if !inputText.isEmpty {
                inputText = ""
                return nil
            }
        }

        if event.modifierFlags.contains(.command),
           event.modifierFlags.contains(.shift),
           event.charactersIgnoringModifiers?.lowercased() == "m" {
            toggleChatVoiceRecording()
            return nil
        }

        return event
    }

    private func toggleChatVoiceRecording() {
        if showingVoiceRecording {
            acceptChatVoiceRecording()
        } else {
            startChatVoiceRecording()
        }
    }

    private func startChatVoiceRecording() {
        Task {
            do {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    showingVoiceRecording = true
                }
                try await viewModel.audioService.startRecording()
            } catch {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    showingVoiceRecording = false
                }
                if let recordingError = error as? AudioService.RecordingError {
                    permissionErrorMessage = recordingError.localizedDescription + "\n\nPlease enable Microphone and Speech Recognition permissions in System Settings."
                } else {
                    permissionErrorMessage = error.localizedDescription
                }
                showingPermissionError = true
            }
        }
    }

    private func acceptChatVoiceRecording() {
        Task {
            let text = await viewModel.audioService.stopRecording()
            let finalText = text.isEmpty ? viewModel.audioService.partialTranscription : text
            await MainActor.run {
                if !finalText.isEmpty {
                    inputText = finalText
                }
                showingVoiceRecording = false
            }
        }
    }

    private func cancelChatVoiceRecording() {
        viewModel.audioService.cancelRecording()
        showingVoiceRecording = false
    }

    // MARK: - Input Handling

    private func sendMessage() {
        let text = inputText
        inputText = ""
        viewModel.sendMessage(text)
    }

    private func handleAutocompleteSelection() {
        guard let (replacement, range) = viewModel.autocompleteHandler.selectCurrent() else { return }
        let nsString = inputText as NSString
        inputText = nsString.replacingCharacters(in: range, with: replacement)
        pendingCursorPosition = range.location + replacement.count
    }

    // MARK: - Autocomplete Window

    private func setupAutocompleteWindow() {
        let window = AutocompleteWindowController()
        window.configureActions(
            onTap: { item in
                // Defer to avoid "Publishing changes from within view updates" warning
                Task { @MainActor in
                    viewModel.autocompleteHandler.selectItem(item)
                    handleAutocompleteSelection()
                }
            },
            onSelect: {
                handleAutocompleteSelection()
            }
        )
        autocompleteWindow = window
    }

    private func updateAutocompleteWindow(state: AutocompleteState) {
        guard let window = autocompleteWindow else { return }

        // Find parent window - try keyWindow, mainWindow, or any window
        let parentWindow = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible })

        // Show window when active (even if items empty - shows "no matches")
        if state.isActive, let parentWindow = parentWindow {
            window.update(state: state)
            window.show(at: state.cursorRect, attachedTo: parentWindow)
        } else {
            window.dismiss()
        }
    }
}
