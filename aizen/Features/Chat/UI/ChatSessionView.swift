//
//  ChatSessionView.swift
//  aizen
//
//  Chat session interface with messages and input
//

import ACP
import CoreData
import SwiftUI
import VVChatTimeline

struct ChatSessionView: View {
    let worktree: Worktree
    @ObservedObject var session: ChatSession
    let sessionManager: ChatSessionRegistry
    let isSelected: Bool
    let isCompanionResizing: Bool

    @Environment(\.managedObjectContext) var viewContext

    @StateObject var viewModel: ChatSessionStore

    // UI-only state
    @State var showingVoiceRecording = false
    @State var showingPermissionError = false
    @State var permissionErrorMessage = ""
    @State private var showingUsageSheet = false
    @State var autocompleteWindow: AutocompleteWindowController?
    @State var keyMonitor: Any?
    @State var chatActions = ChatActions()
    @State private var isWindowResizing = false
    @State private var wasNearBottomBeforeResize = true
    @State var chatTimelineState = VVChatTimelineState()

    // Input state (local to avoid re-rendering entire view on keystroke)
    @State var inputText = ""
    @State var pendingCursorPosition: Int?
    @State private var isInlinePlanCollapsed = true
    @State var inputBarWidth: CGFloat = 0

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
        sessionManager: ChatSessionRegistry,
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

        let vm = ChatSessionStore(
            worktree: worktree,
            session: session,
            sessionManager: sessionManager,
            viewContext: viewContext
        )
        self._viewModel = StateObject(wrappedValue: vm)
    }

    var body: some View {
        let isLayoutResizing = isWindowResizing || isCompanionResizing
        applyLifecycleModifiers(to:
        ZStack {
            Color.clear
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ZStack(alignment: .bottom) {
                    ChatTimelineContainer(
                        key: timelineRenderKey,
                        messages: viewModel.messages,
                        toolCalls: viewModel.toolCalls,
                        isStreaming: viewModel.currentAgentSession?.isStreaming ?? false,
                        isSessionInitializing: viewModel.isSessionInitializing,
                        pendingPlanRequest: pendingPlanTimelineRequest,
                        worktreePath: worktree.path,
                        selectedAgent: viewModel.selectedAgent,
                        scrollRequest: viewModel.scrollRequest,
                        isAutoScrollEnabled: { !viewModel.userScrolledUp },
                        onAppear: viewModel.loadMessages,
                        onTimelineStateChange: { state in
                            chatTimelineState = state
                            viewModel.enqueueScrollPositionChange(
                                state.isLiveTail,
                                isLayoutResizing: isLayoutResizing
                            )
                        }
                    )
                    .equatable()
                    .padding(.horizontal, 20)
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
                                    .task(id: geometry.size.width) {
                                        updateInputBarWidth(geometry.size.width)
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
                            SessionsWindowController.shared.show(context: viewContext, worktreeId: worktree.id)
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
        .task(id: isLayoutResizing) {
            // Defer to avoid publishing ObservableObject changes during an active view update/layout pass.
            DispatchQueue.main.async {
                handleLayoutResizingChange(isLayoutResizing)
            }
        }
        )
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

    private func updateInputBarWidth(_ width: CGFloat) {
        let normalized = max((width * 2).rounded() / 2, 0)
        guard abs(normalized - inputBarWidth) > 0.5 else { return }

        // Geometry changes can arrive during layout; defer state mutation to next run loop.
        DispatchQueue.main.async {
            guard abs(normalized - inputBarWidth) > 0.5 else { return }
            inputBarWidth = normalized
        }
    }

    private func handleLayoutResizingChange(_ resizing: Bool) {
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

    var currentPermissionRequest: RequestPermissionRequest? {
        guard viewModel.showingPermissionAlert,
              let request = viewModel.currentPermissionRequest else {
            return nil
        }
        return request
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

    // MARK: - Autocomplete Window
}
