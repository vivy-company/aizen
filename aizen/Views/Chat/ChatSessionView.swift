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
    @State private var showingAuthSheet = false
    @State private var showingCommandAutocomplete = false
    @State private var showingVoiceRecording = false
    @State private var showingPermissionError = false
    @State private var permissionErrorMessage = ""
    @State private var showingAgentSetupDialog = false
    @State private var showingAgentPlan = false
    @State private var showingUpdateSheet = false

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
                        selectedAgent: viewModel.selectedAgent,
                        currentThought: viewModel.currentAgentSession?.currentThought,
                        onScrollProxyReady: { proxy in
                            viewModel.scrollProxy = proxy
                        },
                        onAppear: viewModel.loadMessages,
                        renderInlineMarkdown: viewModel.renderInlineMarkdown
                    )

                    Spacer(minLength: 0)

                    VStack(spacing: 8) {
                        // Permission Requests (excluding plan requests - those show as sheet)
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
                            showingCommandAutocomplete: $showingCommandAutocomplete,
                            showingPermissionError: $showingPermissionError,
                            permissionErrorMessage: $permissionErrorMessage,
                            commandSuggestions: viewModel.commandSuggestions,
                            session: viewModel.currentAgentSession,
                            currentModeId: viewModel.currentModeId,
                            selectedAgent: viewModel.selectedAgent,
                            isSessionReady: viewModel.isSessionReady,
                            audioService: viewModel.audioService,
                            onSend: viewModel.sendMessage,
                            onCancel: viewModel.cancelCurrentPrompt,
                            onCommandSelect: viewModel.selectCommand
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
            NotificationCenter.default.post(name: .chatViewDidAppear, object: nil)
        }
        .onChange(of: viewModel.selectedAgent) { _ in
            viewModel.setupAgentSession()
        }
        .onChange(of: viewModel.inputText) { newText in
            viewModel.updateCommandSuggestions(newText)
            updateCommandAutocompleteVisibility()
        }
        .onReceive(NotificationCenter.default.publisher(for: .cycleModeShortcut)) { _ in
            viewModel.cycleModeForward()
        }
        .onReceive(NotificationCenter.default.publisher(for: .interruptAgentShortcut)) { _ in
            viewModel.cancelCurrentPrompt()
        }
        .onDisappear {
            NotificationCenter.default.post(name: .chatViewDidDisappear, object: nil)
        }
        // Direct observers for derived/nested state (fixes Issue 2: triggers on async changes)
        .onReceive(viewModel.$needsAuth) { needsAuth in
            if needsAuth {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    showingAuthSheet = true
                }
            }
        }
        .onReceive(viewModel.$needsSetup) { needsSetup in
            if needsSetup {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    showingAgentSetupDialog = true
                }
            }
        }
        .onReceive(viewModel.$needsUpdate) { needsUpdate in
            if needsUpdate {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    showingUpdateSheet = true
                }
            }
        }
        .onReceive(viewModel.$hasAgentPlan) { hasPlan in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                showingAgentPlan = hasPlan
            }
        }
        .onReceive(viewModel.$showingPermissionAlert) { showing in
            // Check if this is a plan request - if so, show as sheet instead of inline
            if showing, let request = viewModel.currentPermissionRequest, isPlanRequest(request) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    showingAgentPlan = true
                }
            }
        }
        .sheet(isPresented: $showingAuthSheet) {
            if let agentSession = viewModel.currentAgentSession {
                AuthenticationSheet(session: agentSession)
            }
        }
        .sheet(isPresented: $showingAgentSetupDialog) {
            if let agentSession = viewModel.currentAgentSession {
                AgentSetupDialog(session: agentSession)
            }
        }
        .sheet(isPresented: $showingUpdateSheet) {
            if let versionInfo = viewModel.versionInfo {
                AgentUpdateSheet(
                    agentName: viewModel.selectedAgent,
                    versionInfo: versionInfo
                )
            }
        }
        .sheet(isPresented: $showingAgentPlan) {
            // Check if this is a plan approval request or plan progress view
            if let request = viewModel.currentPermissionRequest,
               isPlanRequest(request),
               let agentSession = viewModel.currentAgentSession {
                // Plan approval - show approval dialog
                PlanApprovalDialog(
                    session: agentSession,
                    request: request,
                    isPresented: $showingAgentPlan
                )
            } else if let plan = viewModel.currentAgentPlan {
                // Plan progress - show progress dialog
                AgentPlanDialog(plan: plan, isPresented: $showingAgentPlan)
                    .frame(minWidth: 500, minHeight: 400)
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
            ForEach(viewModel.attachments, id: \.self) { attachment in
                AttachmentChipWithDelete(url: attachment) {
                    viewModel.removeAttachment(attachment)
                }
            }
            Spacer()
        }
    }

    // MARK: - Helpers

    private func updateCommandAutocompleteVisibility() {
        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
            showingCommandAutocomplete = !viewModel.commandSuggestions.isEmpty
        }
    }
}
