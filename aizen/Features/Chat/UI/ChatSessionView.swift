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
    @State var showingUsageSheet = false
    @State var autocompleteWindow: AutocompleteWindowController?
    @State var keyMonitor: Any?
    @State var chatActions = ChatActions()
    @State private var isWindowResizing = false
    @State var wasNearBottomBeforeResize = true
    @State var chatTimelineState = VVChatTimelineState()

    // Input state (local to avoid re-rendering entire view on keystroke)
    @State var inputText = ""
    @State var pendingCursorPosition: Int?
    @State private var isInlinePlanCollapsed = true
    @State var inputBarWidth: CGFloat = 0

    var supportsUsageMetrics: Bool {
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
        applyPresentationModifiers(to:
        applyLifecycleModifiers(to:
        ZStack {
            Color.clear
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ZStack(alignment: .bottom) {
                    ChatTimelineContainer(
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

                        composerStack
                    }
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
        ))
    }

}
