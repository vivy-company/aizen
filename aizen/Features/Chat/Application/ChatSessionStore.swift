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
    let timelineStore = ChatTimelineStore()

    // MARK: - State

    @Published var isProcessing = false
    @Published var currentAgentSession: ChatAgentSession?
    @Published var currentPermissionRequest: RequestPermissionRequest?
    @Published var attachments: [ChatAttachment] = []

    // Historical messages loaded from Core Data (separate from live session)
    var historicalMessages: [MessageItem] = []
    var historicalToolCalls: [ToolCall] = []

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
    @Published var availableModes: [ModeInfo] = []
    @Published var availableModels: [ModelInfo] = []
    @Published var availableConfigOptions: [SessionConfigOption] = []
    @Published var currentModeId: String?
    @Published var currentModelId: String?
    @Published var sessionState: SessionState = .idle
    @Published var isResumingSession: Bool = false

    // MARK: - Internal State

    var cancellables = Set<AnyCancellable>()
    var notificationCancellables = Set<AnyCancellable>()
    var wasStreaming: Bool = false
    var observedSessionId: UUID?
    let logger = Logger.forCategory("ChatSession")
    var draftPersistTask: Task<Void, Never>?
    var skipNextMessagesEmission: Bool = false
    var skipNextToolCallsEmission: Bool = false
    var gitPauseApplied: Bool = false
    var settingUpSessionId: UUID? = nil
    var hasLoadedWarmState = false
    var hasIndexedAutocompleteWorktree = false
    var indexedAutocompleteWorktreePath = ""
    var delayedActivationTask: Task<Void, Never>?
    let delayedActivationInterval = Duration.milliseconds(160)

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
        delayedActivationTask?.cancel()
        delayedActivationTask = nil
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
    
    // MARK: - Derived State Updates
    func updateDerivedState(from session: ChatAgentSession) {
        needsAuth = session.needsAuthentication
        needsSetup = session.needsAgentSetup
        needsUpdate = session.needsUpdate
        versionInfo = session.versionInfo
        currentAgentPlan = session.agentPlan
        availableModes = session.availableModes
        availableModels = session.availableModels
        availableConfigOptions = session.availableConfigOptions
        currentModeId = session.currentModeId
        currentModelId = session.currentModelId
        sessionState = session.sessionState
        isResumingSession = session.isResumingSession
        showingPermissionAlert = session.permissionHandler.showingPermissionAlert
        currentPermissionRequest = session.permissionHandler.permissionRequest
        timelineStore.isStreaming = session.isStreaming
        timelineStore.isSessionInitializing = session.sessionState.isInitializing
    }

    func clearDerivedState() {
        needsAuth = false
        needsSetup = false
        needsUpdate = false
        versionInfo = nil
        currentAgentPlan = nil
        availableModes = []
        availableModels = []
        availableConfigOptions = []
        currentModeId = nil
        currentModelId = nil
        sessionState = .idle
        isResumingSession = false
        showingPermissionAlert = false
        currentPermissionRequest = nil
        isProcessing = false
        timelineStore.isStreaming = false
        timelineStore.isSessionInitializing = false
    }

}
