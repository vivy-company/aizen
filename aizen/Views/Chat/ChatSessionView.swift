//
//  ChatSessionView.swift
//  aizen
//
//  Chat session interface with messages and input
//

import ACP
import CoreData
import SwiftUI

struct ChatSessionView: View {
    let worktree: Worktree
    @ObservedObject var session: ChatSession
    let sessionManager: ChatSessionManager
    let isSelected: Bool
    let isCompanionResizing: Bool

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
    @State private var isWindowResizing = false
    @State private var wasNearBottomBeforeResize = true

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
        isSelected: Bool,
        isCompanionResizing: Bool = false
    ) {
        self.worktree = worktree
        self.session = session
        self.sessionManager = sessionManager
        self.isSelected = isSelected
        self.isCompanionResizing = isCompanionResizing
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
        let isLayoutResizing = isWindowResizing || isCompanionResizing
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ZStack(alignment: .bottom) {
                    ChatMessageList(
                        timelineItems: viewModel.timelineItems,
                        isProcessing: viewModel.isProcessing,
                        isSessionInitializing: viewModel.isSessionInitializing,
                        pendingPlanRequest: pendingPlanTimelineRequest,
                        selectedAgent: viewModel.selectedAgent,
                        currentThought: viewModel.currentAgentSession?.currentThought,
                        currentIterationId: viewModel.currentAgentSession?.currentIterationId,
                        scrollRequest: viewModel.scrollRequest,
                        turnAnchorMessageId: viewModel.turnAnchorMessageId,
                        shouldAutoScroll: viewModel.isNearBottom,
                        isResizing: isLayoutResizing,
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
                            if !isLayoutResizing {
                                if viewModel.isNearBottom != isNearBottom {
                                    viewModel.isNearBottom = isNearBottom
                                }
                            }
                        },
                        childToolCallsProvider: { parentId in
                            viewModel.childToolCalls(for: parentId)
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)

                    if shouldShowScrollToBottom {
                        scrollToBottomButton
                            .padding(.bottom, 16)
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                }

                Spacer(minLength: 0)

                VStack(spacing: 10) {
                    if let agentSession = viewModel.currentAgentSession,
                       let request = currentPermissionRequest {
                        PlanApprovalPickerView(
                            session: agentSession,
                            request: request,
                            onDismissWithoutResponse: { viewModel.showingPermissionAlert = false }
                        )
                        .transition(.opacity)
                        .padding(.horizontal, 20)
                    } else {
                        if pendingPlanTimelineRequest == nil,
                           let plan = viewModel.currentAgentPlan {
                            AgentPlanInlineView(plan: plan)
                                .padding(.horizontal, 20)
                                .transition(.opacity)
                        }

                        if !viewModel.attachments.isEmpty {
                            ChatAttachmentsBar(
                                attachments: viewModel.attachments,
                                onRemoveAttachment: viewModel.removeAttachment
                            )
                            .padding(.horizontal, 20)
                        }

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
                            isRestoringSession: viewModel.isResumingSession,
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

                    ChatControlsBar(
                        currentAgentSession: viewModel.currentAgentSession,
                        hasModes: viewModel.hasModes,
                        onShowUsage: { showingUsageSheet = true },
                        onShowHistory: {
                            SessionsWindowManager.shared.show(context: viewContext, worktreeId: worktree.id)
                        },
                        showsUsage: supportsUsageMetrics
                    )
                    .padding(.horizontal, 20)
                }
                .padding(.top, 12)
                .padding(.bottom, 20)
            }
            .frame(maxWidth: 940)
            .frame(maxWidth: .infinity)
        }
        .background(WindowResizeObserver(isResizing: $isWindowResizing))
        .focusedSceneValue(\.chatActions, ChatActions(cycleModeForward: viewModel.cycleModeForward))
        .onChange(of: isLayoutResizing) { _, resizing in
            if resizing {
                wasNearBottomBeforeResize = viewModel.isNearBottom
                viewModel.cancelPendingAutoScroll()
                viewModel.suppressNextAutoScroll = true
                viewModel.scrollRequest = nil
                viewModel.isNearBottom = false
            } else {
                viewModel.isNearBottom = wasNearBottomBeforeResize
            }
        }
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
            viewModel.cancelPendingAutoScroll()
            viewModel.scrollRequest = nil
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
                viewModel.cancelPendingAutoScroll()
                viewModel.scrollRequest = nil
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

    private var pendingPlanTimelineRequest: RequestPermissionRequest? {
        guard let request = viewModel.currentPermissionRequest,
              isPlanRequest(request) else {
            return nil
        }
        return request
    }

    private var currentPermissionRequest: RequestPermissionRequest? {
        guard viewModel.showingPermissionAlert,
              let request = viewModel.currentPermissionRequest else {
            return nil
        }
        return request
    }

    private var shouldShowScrollToBottom: Bool {
        !viewModel.isNearBottom && !viewModel.timelineItems.isEmpty
    }

    private func scrollToBottom() {
        viewModel.isNearBottom = true
        viewModel.scrollToBottom()
    }

    @ViewBuilder
    private var scrollToBottomButton: some View {
        Button(action: scrollToBottom) {
            if #available(macOS 26.0, *) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.primary)
                    .padding(10)
                    .glassEffect(.regular, in: Circle())
                    .contentShape(Circle())
            } else {
                Image(systemName: "arrow.down")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.primary)
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(
                        Circle()
                            .strokeBorder(.separator.opacity(0.3), lineWidth: 0.5)
                    )
                    .contentShape(Circle())
            }
        }
        .buttonStyle(.plain)
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

        if event.keyCode == keyCodeEscape, let permissionRequest = currentPermissionRequest {
            handlePermissionPickerEscape(request: permissionRequest)
            return nil
        }

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

    private func handlePermissionPickerEscape(request: RequestPermissionRequest) {
        if viewModel.isProcessing {
            viewModel.cancelCurrentPrompt()
        }

        if let optionId = preferredPermissionDismissOptionId(for: request),
           let agentSession = viewModel.currentAgentSession {
            agentSession.respondToPermission(optionId: optionId)
        } else if let agentSession = viewModel.currentAgentSession {
            // Ensure ESC always resolves a pending permission request.
            agentSession.permissionHandler.cancelPendingRequest()
        } else {
            viewModel.showingPermissionAlert = false
        }
    }

    private func preferredPermissionDismissOptionId(for request: RequestPermissionRequest) -> String? {
        guard let options = request.options, !options.isEmpty else {
            return nil
        }
        if let dismissOption = options.first(where: { isPermissionDismissOptionKind($0.kind) }) {
            return dismissOption.optionId
        }
        return options.last?.optionId
    }

    private func isPermissionDismissOptionKind(_ kind: String) -> Bool {
        let normalized = kind.lowercased()
        return normalized.contains("reject")
            || normalized.contains("deny")
            || normalized.contains("cancel")
            || normalized.contains("decline")
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
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if ClientCommandHandler.shared.handle(text, context: viewContext) {
            inputText = ""
            return
        }
        
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
