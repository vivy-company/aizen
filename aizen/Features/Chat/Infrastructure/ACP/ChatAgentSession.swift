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
    private var finalizeMessageTask: Task<Void, Never>?
    
    // Session persistence
    var chatSessionId: UUID?  // Core Data ChatSession ID for persistence
    private var lastAgentChunkAt: Date?
    private static let finalizeIdleDelay: TimeInterval = 0.2
    var isModeChanging = false
    @Published var isResumingSession = false
    var resumeReplayAgentMessages: [String] = []
    var resumeReplayIndex: Int = 0
    var resumeReplayBuffer: String = ""
    var suppressResumedAgentMessages = false
    var persistedToolCallIds: Set<String> = []
    private var thoughtBuffer: String = ""
    private var thoughtFlushTask: Task<Void, Never>?
    private static let thoughtUpdateInterval: TimeInterval = 0.06
    private var pendingAgentText: String = ""
    private var pendingAgentBlocks: [ContentBlock] = []
    private var agentMessageFlushTask: Task<Void, Never>?
    private static let agentMessageFlushInterval: TimeInterval = 0.0

    /// Currently pending Task tool calls (subagents) - used for parent tracking
    /// When only one Task is active, child tool calls are assigned to it
    /// When multiple Tasks are active (parallel), we cannot reliably assign parents
    var activeTaskIds: [String] = []
    /// Buffer tool call updates that arrive before the tool call itself
    var pendingToolCallUpdatesById: [String: [ToolCallUpdateDetails]] = [:]

    // Delegates
    let terminalDelegate = AgentTerminalDelegate()
    let permissionHandler = AgentPermissionHandler()
    private var clientDelegateBridge: ChatAgentSessionClientDelegate!
    var agentCapabilities: AgentCapabilities?
    var promptCapabilities: PromptCapabilities? { agentCapabilities?.promptCapabilities }

    // MARK: - Initialization

    init(agentName: String = "", workingDirectory: String = "") {
        self.agentName = agentName
        self.workingDirectory = workingDirectory
        self.clientDelegateBridge = ChatAgentSessionClientDelegate(session: self)
    }

    // MARK: - Streaming Finalization

    func resetFinalizeState() {
        finalizeMessageTask?.cancel()
        finalizeMessageTask = nil
        lastAgentChunkAt = nil
    }

    func appendThoughtChunk(_ text: String) {
        thoughtBuffer += text
        scheduleThoughtFlush()
    }

    func clearThoughtBuffer() {
        thoughtBuffer = ""
        thoughtFlushTask?.cancel()
        thoughtFlushTask = nil
        if currentThought != nil {
            currentThought = nil
        }
    }

    private func scheduleThoughtFlush() {
        guard thoughtFlushTask == nil else { return }
        thoughtFlushTask = Task { @MainActor in
            defer { thoughtFlushTask = nil }
            try? await Task.sleep(for: .seconds(Self.thoughtUpdateInterval))
            let nextThought: String? = thoughtBuffer.isEmpty ? nil : thoughtBuffer
            if currentThought != nextThought {
                currentThought = nextThought
            }
        }
    }

    func appendAgentMessageChunk(text: String, contentBlocks: [ContentBlock]) {
        pendingAgentText += text
        if !contentBlocks.isEmpty {
            pendingAgentBlocks.append(contentsOf: contentBlocks)
        }
        scheduleAgentMessageFlush()
    }

    func flushAgentMessageBuffer() {
        guard !pendingAgentText.isEmpty || !pendingAgentBlocks.isEmpty else { return }
        agentMessageFlushTask?.cancel()
        agentMessageFlushTask = nil

        if let lastIndex = messages.lastIndex(where: { $0.role == .agent && !$0.isComplete }) {
            let lastAgentMessage = messages[lastIndex]
            let newContent = lastAgentMessage.content + pendingAgentText
            var newBlocks = lastAgentMessage.contentBlocks
            if !pendingAgentBlocks.isEmpty {
                newBlocks.append(contentsOf: pendingAgentBlocks)
            }
            let updatedMessage = MessageItem(
                id: lastAgentMessage.id,
                role: .agent,
                content: newContent,
                timestamp: lastAgentMessage.timestamp,
                toolCalls: lastAgentMessage.toolCalls,
                contentBlocks: newBlocks,
                isComplete: false,
                startTime: lastAgentMessage.startTime,
                executionTime: lastAgentMessage.executionTime,
                requestId: lastAgentMessage.requestId
            )
            var updatedMessages = messages
            updatedMessages[lastIndex] = updatedMessage
            messages = updatedMessages
        }

        pendingAgentText = ""
        pendingAgentBlocks = []
    }

    func clearAgentMessageBuffer() {
        pendingAgentText = ""
        pendingAgentBlocks = []
        agentMessageFlushTask?.cancel()
        agentMessageFlushTask = nil
    }

    private func scheduleAgentMessageFlush() {
        if Self.agentMessageFlushInterval == 0 {
            flushAgentMessageBuffer()
            return
        }

        guard agentMessageFlushTask == nil else { return }
        agentMessageFlushTask = Task { @MainActor in
            defer { agentMessageFlushTask = nil }
            try? await Task.sleep(for: .seconds(Self.agentMessageFlushInterval))
            flushAgentMessageBuffer()
        }
    }

    func recordAgentChunk() {
        lastAgentChunkAt = Date()
    }

    func scheduleFinalizeLastMessage() {
        finalizeMessageTask?.cancel()
        finalizeMessageTask = Task { @MainActor in
            while true {
                let delay: TimeInterval
                if let last = lastAgentChunkAt {
                    let elapsed = Date().timeIntervalSince(last)
                    delay = max(0.0, Self.finalizeIdleDelay - elapsed)
                } else {
                    delay = Self.finalizeIdleDelay
                }

                if delay > 0 {
                    try? await Task.sleep(for: .seconds(delay))
                }

                guard !Task.isCancelled else { return }

                if let last = lastAgentChunkAt,
                   Date().timeIntervalSince(last) < Self.finalizeIdleDelay {
                    continue
                }

                markLastMessageComplete()
                return
            }
        }
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
            self.authMethods = authMethods

            // Check if we should skip authentication (previously succeeded without explicit auth)
            let shouldSkipAuth = AgentRegistry.shared.shouldSkipAuth(for: agentName)

            if shouldSkipAuth {
                // User has previously authenticated externally (e.g., claude /login)
                // Try session directly with normal timeout
                do {
                    try await createSessionDirectly(workingDir: workingDir, client: client)
                    return
                } catch {
                    // Auth may have expired, clear skip preference and show dialog
                    AgentRegistry.shared.clearAuthPreference(for: agentName)
                    // Fall through to show auth dialog
                }
            } else if let savedAuthMethod = AgentRegistry.shared.getAuthPreference(for: agentName) {
                // Try saved auth method
                do {
                    try await performAuthentication(
                        client: client, authMethodId: savedAuthMethod, workingDir: workingDir)
                    return
                } catch {
                    addSystemMessage(
                        "⚠️ Saved authentication method failed. Please re-authenticate.")
                    AgentRegistry.shared.clearAuthPreference(for: agentName)
                    // Fall through to show auth dialog
                }
            } else {
                // No saved preference - try session without auth first (user may have logged in externally)
                do {
                    try await createSessionDirectly(workingDir: workingDir, client: client)
                    // Success! Save skip preference for future sessions
                    AgentRegistry.shared.saveSkipAuth(for: agentName)
                    return
                } catch {
                    // Check if error indicates API key/custom endpoint issue
                    let errorMessage = error.localizedDescription.lowercased()
                    if isAuthRequiredError(error) {
                        self.needsAuthentication = true
                        if errorMessage.contains("api key") || errorMessage.contains("invalid") ||
                            errorMessage.contains("unauthorized") || errorMessage.contains("401") {
                            addSystemMessage("⚠️ \(error.localizedDescription)")
                        } else {
                            addSystemMessage("Authentication required. Use the login button or configure API keys in environment variables.")
                        }
                        return
                    }
                    // Fall through to show auth dialog for other errors
                }
            }

            // Show auth dialog
            self.needsAuthentication = true
            addSystemMessage("Authentication required. Use the login button or configure API keys in environment variables.")
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

        self.sessionId = sessionResponse.sessionId
        // Mark as ready only after everything is set up
        self.sessionState = .ready

        if let modesInfo = sessionResponse.modes {
            self.availableModes = modesInfo.availableModes
            self.currentModeId = modesInfo.currentModeId
        }

        if let modelsInfo = sessionResponse.models {
            self.availableModels = modelsInfo.availableModels
            self.currentModelId = modelsInfo.currentModelId
        }

        if let configOptions = sessionResponse.configOptions {
            self.availableConfigOptions = configOptions
        }

        let metadata = AgentRegistry.shared.getMetadata(for: agentName)
        let displayName = metadata?.name ?? agentName
        AgentUsageStore.shared.recordSessionStart(agentId: agentName)
        addSystemMessage("Session started with \(displayName) in \(workingDir)")
        
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
        
        sessionState = .initializing
        isActive = true
        isResumingSession = true
        suppressResumedAgentMessages = true
        prepareResumeReplayState()
        self.chatSessionId = chatSessionId
        
        guard !acpSessionId.isEmpty,
              acpSessionId.count < 256,
              acpSessionId.allSatisfy({ $0.isASCII && !$0.isNewline }) else {
            sessionState = .failed("Invalid ACP session ID format")
            isActive = false
            isResumingSession = false
            clearResumeReplayState()
            throw AgentSessionError.custom("Invalid ACP session ID format")
        }
        
        guard FileManager.default.fileExists(atPath: workingDir) else {
            sessionState = .failed("Working directory no longer exists: \(workingDir)")
            isActive = false
            isResumingSession = false
            clearResumeReplayState()
            throw AgentSessionError.custom("Working directory no longer exists: \(workingDir)")
        }
        
        guard FileManager.default.isReadableFile(atPath: workingDir) else {
            sessionState = .failed("Working directory not accessible: \(workingDir)")
            isActive = false
            isResumingSession = false
            clearResumeReplayState()
            throw AgentSessionError.custom("Working directory not accessible: \(workingDir)")
        }
        
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
            isResumingSession = false
            clearResumeReplayState()
            throw error
        }

        let canLoadSession = initResponse.agentCapabilities.loadSession ?? false
        guard canLoadSession else {
            isActive = false
            isResumingSession = false
            clearResumeReplayState()
            sessionState = .failed("Agent does not support session resume")
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
            isActive = false
            isResumingSession = false
            clearResumeReplayState()
            sessionState = .failed("loadSession failed: \(error.localizedDescription)")
            self.acpClient = nil
            throw error
        }
        
        self.sessionId = sessionResponse.sessionId
        self.sessionState = .ready

        if let modesInfo = sessionResponse.modes {
            self.availableModes = modesInfo.availableModes
            self.currentModeId = modesInfo.currentModeId
        }

        if let modelsInfo = sessionResponse.models {
            self.availableModels = modelsInfo.availableModels
            self.currentModelId = modelsInfo.currentModelId
        }

        if let configOptions = sessionResponse.configOptions {
            self.availableConfigOptions = configOptions
        }
        
        let metadata = AgentRegistry.shared.getMetadata(for: agentName)
        let displayName = metadata?.name ?? agentName
        AgentUsageStore.shared.recordSessionStart(agentId: agentName)
        addSystemMessage("Session resumed with \(displayName) in \(workingDir)")
        
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            self.isResumingSession = false
            self.clearResumeReplayState()
        }
    }

    private func initializeClient(
        agentName: String,
        workingDir: String,
        startTime: CFAbsoluteTime,
        previousAgentName: String,
        previousWorkingDir: String
    ) async throws -> (client: Client, initResponse: InitializeResponse) {
        let agentPath = AgentRegistry.shared.getAgentPath(for: agentName)
        let isValid = AgentRegistry.shared.validateAgent(named: agentName)
        
        guard let agentPath = agentPath, isValid else {
            needsAgentSetup = true
            missingAgentName = agentName
            setupError = nil
            sessionState = .failed("Agent not configured")
            throw AgentSessionError.custom("Agent not configured")
        }

        let launchArgs = AgentRegistry.shared.getAgentLaunchArgs(for: agentName)
        let launchEnvironment = await AgentRegistry.shared.resolvedAgentLaunchEnvironment(for: agentName)
        let client = Client()
        await client.setDelegate(clientDelegateBridge)

        do {
            try await client.launch(
                agentPath: agentPath,
                arguments: launchArgs,
                workingDirectory: workingDir,
                environment: launchEnvironment.isEmpty ? nil : launchEnvironment
            )
        } catch {
            isActive = false
            sessionState = .failed(error.localizedDescription)
            self.agentName = previousAgentName
            self.workingDirectory = previousWorkingDir
            self.acpClient = nil
            throw error
        }

        let initResponse: InitializeResponse
        do {
            initResponse = try await client.initialize(
                protocolVersion: 1,
                capabilities: ClientCapabilities(
                    fs: FileSystemCapabilities(
                        readTextFile: true,
                        writeTextFile: true
                    ),
                    terminal: true,
                    meta: [
                        "terminal_output": AnyCodable(true),
                        "terminal-auth": AnyCodable(true)
                    ]
                ),
                timeout: 120.0
            )
        } catch {
            await client.setDelegate(nil)
            await client.terminate()
            isActive = false
            sessionState = .failed("Initialize failed: \(error.localizedDescription)")
            self.agentName = previousAgentName
            self.workingDirectory = previousWorkingDir
            self.acpClient = nil
            throw error
        }

        self.acpClient = client
        startNotificationListener(client: client)
        self.agentCapabilities = initResponse.agentCapabilities

        versionCheckTask = Task { [weak self] in
            guard let self = self else { return }
            let versionInfo = await AgentVersionChecker.shared.checkVersion(for: agentName)
            await MainActor.run {
                self.versionInfo = versionInfo
                if versionInfo.isOutdated {
                    self.needsUpdate = true
                    self.addSystemMessage(
                        "⚠️ Update available: \(agentName) v\(versionInfo.current ?? "?") → v\(versionInfo.latest ?? "?")"
                    )
                }
            }
        }

        return (client, initResponse)
    }
    
    func persistSessionId(chatSessionId: UUID) async throws {
        guard let sessionId = sessionId else {
            return
        }
        
        let context = PersistenceController.shared.container.viewContext
        
        try await ChatSessionPersistence.shared.saveSessionId(
            sessionId.value,
            for: chatSessionId,
            in: context
        )
    }

}
