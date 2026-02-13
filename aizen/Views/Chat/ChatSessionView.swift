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
    @State private var chatActions = ChatActions()
    @State private var isWindowResizing = false
    @State private var wasNearBottomBeforeResize = true

    // Input state (local to avoid re-rendering entire view on keystroke)
    @State private var inputText = ""
    @State private var pendingCursorPosition: Int?
    @State private var isInlinePlanCollapsed = true
    @State private var inputBarWidth: CGFloat = 0

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
                    ChatTimelineContainer(
                        key: timelineRenderKey,
                        timelineItems: viewModel.timelineItems,
                        isProcessing: viewModel.isProcessing,
                        isSessionInitializing: viewModel.isSessionInitializing,
                        pendingPlanRequest: pendingPlanTimelineRequest,
                        selectedAgent: viewModel.selectedAgent,
                        currentThought: viewModel.currentAgentSession?.currentThought,
                        currentIterationId: viewModel.currentAgentSession?.currentIterationId,
                        scrollRequest: viewModel.scrollRequest,
                        turnAnchorMessageId: viewModel.turnAnchorMessageId,
                        isAutoScrollEnabled: { viewModel.isNearBottom },
                        isResizing: isLayoutResizing,
                        onAppear: viewModel.loadMessages,
                        renderInlineMarkdown: viewModel.renderInlineMarkdown,
                        worktreePath: worktree.path,
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
                    .equatable()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)

                    scrollToBottomButton
                        .padding(.bottom, 16)
                        .opacity(shouldShowScrollToBottom ? 1 : 0)
                        .allowsHitTesting(shouldShowScrollToBottom)
                        .accessibilityHidden(!shouldShowScrollToBottom)
                }

                Spacer(minLength: 0)

                VStack(spacing: 10) {
                    if viewModel.isProcessing {
                        ChatProcessingIndicator(
                            currentThought: viewModel.currentAgentSession?.currentThought,
                            renderInlineMarkdown: viewModel.renderInlineMarkdown
                        )
                        .padding(.horizontal, 28)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

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
                        if let plan = inlinePlan {
                            Group {
                                if let inlinePlanWidth {
                                    AgentPlanInlineView(
                                        plan: plan,
                                        isCollapsed: $isInlinePlanCollapsed,
                                        isAttachedToComposer: shouldAttachInlinePlanToInput
                                    )
                                    .frame(width: inlinePlanWidth)
                                } else {
                                    AgentPlanInlineView(
                                        plan: plan,
                                        isCollapsed: $isInlinePlanCollapsed,
                                        isAttachedToComposer: shouldAttachInlinePlanToInput
                                    )
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.horizontal, 20)
                            .padding(.bottom, shouldAttachInlinePlanToInput ? -10 : 0)
                            .transition(.opacity)
                        }

                        if !viewModel.attachments.isEmpty {
                            ChatAttachmentsBar(
                                attachments: viewModel.attachments,
                                onRemoveAttachment: { index in
                                    viewModel.removeAttachment(at: index)
                                }
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
                                let maxImageSizeBytes = 10 * 1024 * 1024
                                guard data.count <= maxImageSizeBytes else {
                                    let sizeText = ByteCountFormatter.string(
                                        fromByteCount: Int64(data.count),
                                        countStyle: .file
                                    )
                                    viewModel.currentAgentSession?.addSystemMessage(
                                        "Pasted image is too large (\(sizeText)). Maximum size is 10MB."
                                    )
                                    return
                                }
                                viewModel.attachments.append(.image(data, mimeType: mimeType))
                            },
                            onFilePaste: { url in
                                viewModel.attachments.append(.file(url))
                            },
                            onAgentSelect: viewModel.requestAgentSwitch
                        )
                        .background {
                            GeometryReader { geometry in
                                Color.clear
                                    .onAppear {
                                        inputBarWidth = geometry.size.width
                                    }
                                    .onChange(of: geometry.size.width) { _, newWidth in
                                        inputBarWidth = newWidth
                                    }
                            }
                        }
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
        .focusedSceneValue(
            \.chatActions,
            isSelected ? chatActions : nil
        )
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
                chatActions.configure(cycleModeForward: viewModel.cycleModeForward)
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
            chatActions.clear()
            if showingVoiceRecording {
                viewModel.audioService.cancelRecording()
                showingVoiceRecording = false
            }
        }
        .onChange(of: isSelected) { _, selected in
            if selected {
                chatActions.configure(cycleModeForward: viewModel.cycleModeForward)
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
                chatActions.clear()
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
            let normalizedPath = normalizedEditorPath(path)
            NotificationCenter.default.post(
                name: .openFileInEditor,
                object: nil,
                userInfo: ["path": normalizedPath]
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

    private func normalizedEditorPath(_ path: String) -> String {
        let stripped = stripLineColumnSuffix(from: path)
        let expanded = (stripped as NSString).expandingTildeInPath

        if expanded.hasPrefix("/") {
            return URL(fileURLWithPath: expanded).standardizedFileURL.path
        }

        if let worktreePath = worktree.path, !worktreePath.isEmpty {
            return URL(fileURLWithPath: worktreePath)
                .appendingPathComponent(expanded)
                .standardizedFileURL
                .path
        }

        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(expanded)
            .standardizedFileURL
            .path
    }

    private func stripLineColumnSuffix(from path: String) -> String {
        let parts = path.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return path }

        if Int(parts[parts.count - 1]) != nil {
            if parts.count >= 3, Int(parts[parts.count - 2]) != nil {
                return parts.dropLast(2).joined(separator: ":")
            }
            return parts.dropLast().joined(separator: ":")
        }

        return path
    }

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

    private var pendingPlanTimelineRequestIdentity: String {
        guard let request = pendingPlanTimelineRequest else { return "none" }
        let optionIds = (request.options ?? []).map(\.optionId).joined(separator: "|")
        let toolId = request.toolCall?.toolCallId ?? "none"
        return "req-\(toolId)-\(optionIds)-\(request.message ?? "")"
    }

    private var timelineRenderKey: ChatTimelineRenderKey {
        ChatTimelineRenderKey(
            timelineRenderEpoch: viewModel.timelineRenderEpoch,
            childToolCallsEpoch: viewModel.childToolCallsEpoch,
            isProcessing: viewModel.isProcessing,
            isSessionInitializing: viewModel.isSessionInitializing,
            pendingPlanRequestIdentity: pendingPlanTimelineRequestIdentity,
            selectedAgent: viewModel.selectedAgent,
            currentThought: viewModel.currentAgentSession?.currentThought,
            currentIterationId: viewModel.currentAgentSession?.currentIterationId,
            scrollRequestId: viewModel.scrollRequest?.id,
            turnAnchorMessageId: viewModel.turnAnchorMessageId,
            isResizing: isWindowResizing || isCompanionResizing
        )
    }

    private var inlinePlan: Plan? {
        guard pendingPlanTimelineRequest == nil,
              let plan = viewModel.currentAgentPlan,
              !plan.entries.isEmpty else {
            return nil
        }

        let completedCount = plan.entries.filter { $0.status == .completed }.count
        guard completedCount < plan.entries.count else {
            return nil
        }

        return plan
    }

    private var shouldAttachInlinePlanToInput: Bool {
        inlinePlan != nil && viewModel.attachments.isEmpty
    }

    private var inlinePlanWidth: CGFloat? {
        guard shouldAttachInlinePlanToInput, inputBarWidth > 0 else {
            return nil
        }
        return inputBarWidth * 0.95
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

private struct ChatTimelineRenderKey: Equatable {
    let timelineRenderEpoch: UInt64
    let childToolCallsEpoch: UInt64
    let isProcessing: Bool
    let isSessionInitializing: Bool
    let pendingPlanRequestIdentity: String
    let selectedAgent: String
    let currentThought: String?
    let currentIterationId: String?
    let scrollRequestId: UUID?
    let turnAnchorMessageId: String?
    let isResizing: Bool
}

private struct ChatTimelineContainer: View, Equatable {
    let key: ChatTimelineRenderKey
    let timelineItems: [TimelineItem]
    let isProcessing: Bool
    let isSessionInitializing: Bool
    let pendingPlanRequest: RequestPermissionRequest?
    let selectedAgent: String
    let currentThought: String?
    let currentIterationId: String?
    let scrollRequest: ChatSessionViewModel.ScrollRequest?
    let turnAnchorMessageId: String?
    let isAutoScrollEnabled: () -> Bool
    let isResizing: Bool
    let onAppear: () -> Void
    let renderInlineMarkdown: (String) -> AttributedString
    let worktreePath: String?
    let onToolTap: (ToolCall) -> Void
    let onOpenFileInEditor: (String) -> Void
    let agentSession: AgentSession?
    let onScrollPositionChange: (Bool) -> Void
    let childToolCallsProvider: (String) -> [ToolCall]

    static func == (lhs: ChatTimelineContainer, rhs: ChatTimelineContainer) -> Bool {
        lhs.key == rhs.key
    }

    var body: some View {
        ChatMessageList(
            timelineItems: timelineItems,
            isProcessing: isProcessing,
            isSessionInitializing: isSessionInitializing,
            pendingPlanRequest: pendingPlanRequest,
            selectedAgent: selectedAgent,
            currentThought: currentThought,
            currentIterationId: currentIterationId,
            scrollRequest: scrollRequest,
            turnAnchorMessageId: turnAnchorMessageId,
            isAutoScrollEnabled: isAutoScrollEnabled,
            isResizing: isResizing,
            onAppear: onAppear,
            renderInlineMarkdown: renderInlineMarkdown,
            worktreePath: worktreePath,
            onToolTap: onToolTap,
            onOpenFileInEditor: onOpenFileInEditor,
            agentSession: agentSession,
            onScrollPositionChange: onScrollPositionChange,
            childToolCallsProvider: childToolCallsProvider
        )
    }
}
