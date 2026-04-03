//
//  ChatSessionStore.swift
//  aizen
//
//  Business logic and state management for chat sessions
//

import ACP
import Combine
import CoreData
import Markdown
import os.log
import SwiftUI

// MARK: - Main Store
@MainActor
class ChatSessionStore: ObservableObject {
    // MARK: - Dependencies

    let worktree: Worktree
    let session: ChatSession
    let sessionManager: ChatSessionRegistry
    let viewContext: NSManagedObjectContext
    private let worktreePathSnapshot: String

    // MARK: - Handlers

    let agentSwitcher: AgentSwitcher
    let autocompleteHandler = UnifiedAutocompleteHandler()

    // MARK: - Services

    @Published var audioService = AudioService()

    // MARK: - State

    @Published var isProcessing = false
    @Published var currentAgentSession: ChatAgentSession?
    @Published var currentPermissionRequest: RequestPermissionRequest?
    @Published var attachments: [ChatAttachment] = []
    @Published var timelineRenderEpoch: UInt64 = 0

    // Track previous IDs for incremental sync (avoids storing full duplicate arrays)
    var previousMessageIds: Set<String> = []
    var previousToolCallIds: Set<String> = []

    // Historical messages loaded from Core Data (separate from live session)
    var historicalMessages: [MessageItem] = []
    var historicalToolCalls: [ToolCall] = []

    var messages: [MessageItem] {
        let source = currentAgentSession?.messages ?? historicalMessages
        
        return source.filter { message in
            guard message.role == .agent else { return true }
            return !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// Tool calls - derives from ChatAgentSession (no duplicate storage)
    var toolCalls: [ToolCall] {
        currentAgentSession?.toolCalls ?? []
    }

    // MARK: - UI State Flags

    @Published var showingPermissionAlert: Bool = false
    @Published var showingAgentSwitchWarning = false
    @Published var pendingAgentSwitch: String?

    // MARK: - Derived State (bridges nested ChatAgentSession properties for reliable observation)
    @Published var needsAuth: Bool = false
    @Published var needsSetup: Bool = false
    @Published var needsUpdate: Bool = false
    @Published var versionInfo: AgentVersionInfo?
    @Published var currentAgentPlan: Plan?
    @Published var hasModes: Bool = false
    @Published var currentModeId: String?
    @Published var sessionState: SessionState = .idle
    @Published var isResumingSession: Bool = false

    // MARK: - Internal State

    @Published var scrollRequest: ScrollRequest?
    @Published var isNearBottom: Bool = true
    /// Tracks user intent: true when user has actively scrolled up away from bottom.
    /// Unlike isNearBottom (which flips on every content change), this only changes
    /// on explicit user scroll gestures or forced scroll-to-bottom actions.
    var userScrolledUp: Bool = false
    var cancellables = Set<AnyCancellable>()
    var notificationCancellables = Set<AnyCancellable>()
    var wasStreaming: Bool = false
    var observedSessionId: UUID?
    let logger = Logger.forCategory("ChatSession")
    var autoScrollTask: Task<Void, Never>?
    var suppressNextAutoScroll: Bool = false
    var pendingStreamingRebuild: Bool = false
    var pendingStreamingRebuildRequiresToolCallSync: Bool = false
    var streamingRebuildTask: Task<Void, Never>?
    private var pendingNearBottomState: Bool?
    private var nearBottomStateTask: Task<Void, Never>?
    var draftPersistTask: Task<Void, Never>?
    var skipNextMessagesEmission: Bool = false
    var skipNextToolCallsEmission: Bool = false
    var gitPauseApplied: Bool = false
    var settingUpSessionId: UUID? = nil

    // MARK: - Computed Properties

    /// Internal agent identifier used for ACP calls
    var selectedAgent: String {
        session.agentName ?? AgentRegistry.defaultAgentID
    }

    /// User-friendly agent name for UI (falls back to id)
    var selectedAgentDisplayName: String {
        if let meta = AgentRegistry.shared.getMetadata(for: selectedAgent) {
            return meta.name
        }
        return selectedAgent
    }

    var isSessionReady: Bool {
        sessionState.isReady && !needsAuth
    }

    var isSessionInitializing: Bool {
        sessionState.isInitializing
    }
    
    // Computed bindings for sheet presentation (prevents recreation on every render)
    var needsAuthBinding: Binding<Bool> {
        Binding(
            get: { self.needsAuth },
            set: { if !$0 { self.needsAuth = false } }
        )
    }
    
    var needsSetupBinding: Binding<Bool> {
        Binding(
            get: { self.needsSetup },
            set: { if !$0 { self.needsSetup = false } }
        )
    }
    
    var needsUpdateBinding: Binding<Bool> {
        Binding(
            get: { self.needsUpdate },
            set: { if !$0 { self.needsUpdate = false } }
        )
    }

    // MARK: - Initialization

    init(
        worktree: Worktree,
        session: ChatSession,
        sessionManager: ChatSessionRegistry,
        viewContext: NSManagedObjectContext
    ) {
        self.worktree = worktree
        self.session = session
        self.sessionManager = sessionManager
        self.viewContext = viewContext
        self.worktreePathSnapshot = worktree.path ?? ""

        self.agentSwitcher = AgentSwitcher(viewContext: viewContext, session: session)

        setupNotificationObservers()
    }

    // MARK: - Lifecycle

    deinit {
        nearBottomStateTask?.cancel()
        nearBottomStateTask = nil
        if gitPauseApplied, !worktreePathSnapshot.isEmpty {
            let path = worktreePathSnapshot
            Task { @MainActor in
                WorktreeRuntimeCoordinator.shared
                    .runtime(for: path)
                    .setGitRefreshSuspended(false)
            }
        }
        cancellables.removeAll()
        notificationCancellables.removeAll()
        observedSessionId = nil
    }

    /// Coalesce bottom-visibility updates to avoid state writes during SwiftUI layout transactions.
    func enqueueScrollPositionChange(_ isNearBottom: Bool, isLayoutResizing: Bool) {
        guard !isLayoutResizing else { return }

        if pendingNearBottomState == isNearBottom, nearBottomStateTask != nil {
            return
        }
        pendingNearBottomState = isNearBottom

        guard nearBottomStateTask == nil else { return }
        nearBottomStateTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            defer { self.nearBottomStateTask = nil }

            guard let nextState = self.pendingNearBottomState else { return }
            self.pendingNearBottomState = nil
            self.applyScrollPositionChange(nextState)
        }
    }

    private func applyScrollPositionChange(_ isNearBottom: Bool) {
        if self.isNearBottom != isNearBottom {
            self.isNearBottom = isNearBottom
        }
        // Mark userScrolledUp when user scrolls away from bottom.
        // Do NOT auto-clear it when near bottom — only cleared explicitly
        // by scrollToBottom() (button click or new turn start).
        if !isNearBottom && !userScrolledUp {
            userScrolledUp = true
        }
    }
    
    // MARK: - Derived State Updates
    func updateDerivedState(from session: ChatAgentSession) {
        needsAuth = session.needsAuthentication
        needsSetup = session.needsAgentSetup
        needsUpdate = session.needsUpdate
        versionInfo = session.versionInfo
        currentAgentPlan = session.agentPlan
        hasModes = !session.availableModes.isEmpty
        currentModeId = session.currentModeId
        sessionState = session.sessionState
        isResumingSession = session.isResumingSession
        showingPermissionAlert = session.permissionHandler.showingPermissionAlert
        currentPermissionRequest = session.permissionHandler.permissionRequest
    }

}
