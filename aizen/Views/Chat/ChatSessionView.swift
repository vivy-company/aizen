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

    @Environment(\.managedObjectContext) private var viewContext

    @StateObject private var viewModel: ChatSessionViewModel

    // UI-only state
    @State private var showingAttachmentPicker = false
    @State private var showingVoiceRecording = false
    @State private var showingPermissionError = false
    @State private var permissionErrorMessage = ""
    @State private var selectedToolCall: ToolCall?
    @State private var fileToOpenInEditor: String?
    @State private var autocompleteWindow: AutocompleteWindowController?

    init(worktree: Worktree, session: ChatSession, sessionManager: ChatSessionManager, viewContext: NSManagedObjectContext) {
        self.worktree = worktree
        self.session = session
        self.sessionManager = sessionManager
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

            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    ChatMessageList(
                        timelineItems: viewModel.timelineItems,
                        isProcessing: viewModel.isProcessing,
                        selectedAgent: viewModel.selectedAgentDisplayName,
                        currentThought: viewModel.currentAgentSession?.currentThought,
                        currentIterationId: viewModel.currentAgentSession?.currentIterationId,
                        onScrollProxyReady: { proxy in
                            viewModel.scrollProxy = proxy
                        },
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

                    Spacer(minLength: 0)

                    VStack(spacing: 8) {
                        // Agent Plan (inline, above permission requests)
                        if let plan = viewModel.currentAgentPlan {
                            HStack {
                                AgentPlanInlineView(plan: plan)
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }

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

                        if !viewModel.attachments.isEmpty {
                            attachmentChipsView
                                .padding(.horizontal, 20)
                        }

                        ChatControlsBar(
                            selectedAgent: viewModel.selectedAgent,
                            currentAgentSession: viewModel.currentAgentSession,
                            hasModes: viewModel.hasModes,
                            onAgentSelect: viewModel.requestAgentSwitch
                        )
                        .padding(.horizontal, 20)

                        ChatInputBar(
                            inputText: $viewModel.inputText,
                            attachments: $viewModel.attachments,
                            isProcessing: $viewModel.isProcessing,
                            showingVoiceRecording: $showingVoiceRecording,
                            showingAttachmentPicker: $showingAttachmentPicker,
                            showingPermissionError: $showingPermissionError,
                            permissionErrorMessage: $permissionErrorMessage,
                            session: viewModel.currentAgentSession,
                            currentModeId: viewModel.currentModeId,
                            selectedAgent: viewModel.selectedAgent,
                            isSessionReady: viewModel.isSessionReady,
                            audioService: viewModel.audioService,
                            autocompleteHandler: viewModel.autocompleteHandler,
                            onSend: viewModel.sendMessage,
                            onCancel: viewModel.cancelCurrentPrompt,
                            onAutocompleteSelect: viewModel.handleAutocompleteSelection
                        )
                        .padding(.horizontal, 20)
                    }
                    .padding(.vertical, 16)
                }


            }
        }
        .focusedSceneValue(\.chatActions, ChatActions(cycleModeForward: viewModel.cycleModeForward))
        .onAppear {
            viewModel.setupAgentSession()
            setupAutocompleteWindow()
            NotificationCenter.default.post(name: .chatViewDidAppear, object: nil)
        }
        .onDisappear {
            autocompleteWindow?.dismiss()
            NotificationCenter.default.post(name: .chatViewDidDisappear, object: nil)
        }
        .onReceive(viewModel.autocompleteHandler.$state) { state in
            updateAutocompleteWindow(state: state)
        }
        .onChange(of: fileToOpenInEditor) { path in
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

    // MARK: - Subviews

    private var attachmentChipsView: some View {
        HStack(spacing: 8) {
            ForEach(viewModel.attachments) { attachment in
                ChatAttachmentChip(attachment: attachment) {
                    viewModel.removeAttachment(attachment)
                }
            }
            Spacer()
        }
    }

    // MARK: - Autocomplete Window

    private func setupAutocompleteWindow() {
        autocompleteWindow = AutocompleteWindowController()
    }

    private func updateAutocompleteWindow(state: AutocompleteState) {
        guard let window = autocompleteWindow,
              let parentWindow = NSApp.keyWindow else { return }

        if state.isActive && !state.items.isEmpty {
            let contentView = InlineAutocompleteView(
                handler: viewModel.autocompleteHandler,
                onSelect: { _ in
                    viewModel.handleAutocompleteSelection()
                }
            )
            window.setContent(contentView)
            window.show(at: state.cursorRect, attachedTo: parentWindow)
        } else {
            window.dismiss()
        }
    }
}
