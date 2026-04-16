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
    let isSelected: Bool
    let isCompanionResizing: Bool

    @Environment(\.managedObjectContext) var viewContext

    @ObservedObject var viewModel: ChatSessionStore

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
        viewModel: ChatSessionStore,
        isSelected: Bool,
        isCompanionResizing: Bool = false
    ) {
        self.worktree = worktree
        self.isSelected = isSelected
        self.isCompanionResizing = isCompanionResizing
        _viewModel = ObservedObject(wrappedValue: viewModel)
    }

    var body: some View {
        let isLayoutResizing = isWindowResizing || isCompanionResizing
        applyPresentationModifiers(to:
        applyLifecycleModifiers(to:
        ZStack {
            Color.clear
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ChatTimelinePane(
                    timelineStore: viewModel.timelineStore,
                    pendingPlanRequest: pendingPlanTimelineRequest,
                    worktreePath: worktree.path,
                    selectedAgent: viewModel.selectedAgent,
                    onAppear: viewModel.loadMessages,
                    isLayoutResizing: isLayoutResizing
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

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
