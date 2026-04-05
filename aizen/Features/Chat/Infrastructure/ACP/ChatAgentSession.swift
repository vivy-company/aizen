//
//  ChatAgentSession.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import ACP
import Combine
import Foundation
import CoreData
import UniformTypeIdentifiers

/// ObservableObject that wraps Client for managing an agent session
@MainActor
class ChatAgentSession: ObservableObject {
    static let maxMessageCount = 500
    static let maxToolCallCount = 500
    // MARK: - Published Properties

    @Published var sessionId: SessionId?
    @Published var agentName: String
    @Published var workingDirectory: String

    // Tool calls stored in dictionary for O(1) lookup, with order array for chronological iteration
    @Published var toolCallsById: [String: ToolCall] = [:]
    @Published var toolCallOrder: [String] = []

    /// Computed property for ordered tool calls array (maintains API compatibility)
    var toolCalls: [ToolCall] {
        toolCallOrder.compactMap { toolCallsById[$0] }
    }

    @Published var messages: [MessageItem] = []
    @Published var currentIterationId: String?
    @Published var isActive: Bool = false
    @Published var sessionState: SessionState = .idle
    @Published var currentThought: String?
    @Published var error: String?
    @Published var isStreaming: Bool = false  // True while prompt request is in progress

    @Published var authMethods: [AuthMethod] = []
    @Published var needsAuthentication: Bool = false
    @Published var availableCommands: [AvailableCommand] = []
    @Published var currentMode: SessionMode?
    @Published var agentPlan: Plan?
    @Published var availableModes: [ModeInfo] = []
    @Published var availableModels: [ModelInfo] = []
    @Published var availableConfigOptions: [SessionConfigOption] = []
    @Published var currentModeId: String?
    @Published var currentModelId: String?

    // Agent setup state
    @Published var needsAgentSetup: Bool = false
    @Published var missingAgentName: String?
    @Published var setupError: String?

    // Version update state
    @Published var needsUpdate: Bool = false
    @Published var versionInfo: AgentVersionInfo?

    // MARK: - Internal Properties

    var acpClient: Client?
    var cancellables = Set<AnyCancellable>()
    var process: Process?
    var notificationTask: Task<Void, Never>?
    var notificationProcessingTask: Task<Void, Never>?
    var versionCheckTask: Task<Void, Never>?
    var finalizeMessageTask: Task<Void, Never>?
    
    // Session persistence
    var chatSessionId: UUID?  // Core Data ChatSession ID for persistence
    var lastAgentChunkAt: Date?
    static let finalizeIdleDelay: TimeInterval = 0.2
    var isModeChanging = false
    @Published var isResumingSession = false
    var resumeReplayAgentMessages: [String] = []
    var resumeReplayIndex: Int = 0
    var resumeReplayBuffer: String = ""
    var suppressResumedAgentMessages = false
    var persistedToolCallIds: Set<String> = []
    var thoughtBuffer: String = ""
    var thoughtFlushTask: Task<Void, Never>?
    static let thoughtUpdateInterval: TimeInterval = 0.06
    var pendingAgentText: String = ""
    var pendingAgentBlocks: [ContentBlock] = []
    var agentMessageFlushTask: Task<Void, Never>?
    static let agentMessageFlushInterval: TimeInterval = 0.0

    /// Currently pending Task tool calls (subagents) - used for parent tracking
    /// When only one Task is active, child tool calls are assigned to it
    /// When multiple Tasks are active (parallel), we cannot reliably assign parents
    var activeTaskIds: [String] = []
    /// Buffer tool call updates that arrive before the tool call itself
    var pendingToolCallUpdatesById: [String: [ToolCallUpdateDetails]] = [:]

    // Delegates
    let terminalDelegate = AgentTerminalDelegate()
    let permissionHandler = AgentPermissionHandler()
    var clientDelegateBridge: ChatAgentSessionClientDelegate!
    var agentCapabilities: AgentCapabilities?
    var promptCapabilities: PromptCapabilities? { agentCapabilities?.promptCapabilities }

    // MARK: - Initialization

    init(agentName: String = "", workingDirectory: String = "") {
        self.agentName = agentName
        self.workingDirectory = workingDirectory
        self.clientDelegateBridge = ChatAgentSessionClientDelegate(session: self)
    }

    // MARK: - Session Management

    /// Start a new agent session
    func start(agentName: String, workingDir: String, chatSessionId: UUID? = nil) async throws {
        guard !isActive && sessionState != .initializing else {
            throw AgentSessionError.sessionAlreadyActive
        }

        sessionState = .initializing
        isActive = true
        self.chatSessionId = chatSessionId

        let startTime = CFAbsoluteTimeGetCurrent()

        let previousAgentName = self.agentName
        let previousWorkingDir = self.workingDirectory

        self.agentName = agentName
        self.workingDirectory = workingDir

        let client: Client
        let initResponse: InitializeResponse
        do {
            (client, initResponse) = try await initializeClient(
                agentName: agentName,
                workingDir: workingDir,
                startTime: startTime,
                previousAgentName: previousAgentName,
                previousWorkingDir: previousWorkingDir
            )
        } catch {
            isActive = false
            throw error
        }

        if let authMethods = initResponse.authMethods, !authMethods.isEmpty {
            if try await handleAuthenticationHandshake(
                authMethods: authMethods,
                agentName: agentName,
                workingDir: workingDir,
                client: client
            ) {
                return
            }
            return
        }

        // Create new session
        let sessionResponse: NewSessionResponse
        do {
            let mcpServers = await resolveMCPServers()
            let sessionTimeout = effectiveSessionTimeout(mcpServers: mcpServers, defaultTimeout: 30.0)
            sessionResponse = try await client.newSession(
                workingDirectory: workingDir,
                mcpServers: mcpServers,
                timeout: sessionTimeout
            )
        } catch {
            isActive = false
            sessionState = .failed("newSession failed: \(error.localizedDescription)")
            self.acpClient = nil
            throw error
        }

        applySessionState(from: sessionResponse)
        announceSessionStart(agentName: agentName, workingDir: workingDir)
        
        if let chatSessionId = chatSessionId {
            do {
                try await persistSessionId(chatSessionId: chatSessionId)
            } catch {
                addSystemMessage("⚠️ Session created but not saved. It may not be available after restart.")
            }
        }
    }
    
    /// Resume an existing agent session from persisted ACP session ID
    func resume(acpSessionId: String, agentName: String, workingDir: String, chatSessionId: UUID) async throws {
        guard !isActive && sessionState != .initializing else {
            throw AgentSessionError.sessionAlreadyActive
        }
        prepareForResume(chatSessionId: chatSessionId)
        try validateResumeRequest(acpSessionId: acpSessionId, workingDir: workingDir)
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        let previousAgentName = self.agentName
        let previousWorkingDir = self.workingDirectory
        
        self.agentName = agentName
        self.workingDirectory = workingDir
        
        let client: Client
        let initResponse: InitializeResponse
        do {
            (client, initResponse) = try await initializeClient(
                agentName: agentName,
                workingDir: workingDir,
                startTime: startTime,
                previousAgentName: previousAgentName,
                previousWorkingDir: previousWorkingDir
            )
        } catch {
            resetResumeState()
            throw error
        }

        let canLoadSession = initResponse.agentCapabilities.loadSession ?? false
        guard canLoadSession else {
            failResume("Agent does not support session resume")
            throw AgentSessionError.sessionResumeUnsupported
        }
        
        let sessionResponse: LoadSessionResponse
        do {
            let mcpServers = await resolveMCPServers()
            sessionResponse = try await client.loadSession(
                sessionId: SessionId(acpSessionId),
                cwd: workingDir,
                mcpServers: mcpServers
            )
        } catch {
            failResume("loadSession failed: \(error.localizedDescription)")
            self.acpClient = nil
            throw error
        }
        
        applySessionState(from: sessionResponse)
        announceSessionResume(agentName: agentName, workingDir: workingDir)
        scheduleResumeReplayCleanup()
    }

}
