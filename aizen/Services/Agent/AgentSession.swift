//
//  AgentSession.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import Combine
import Foundation
import UniformTypeIdentifiers
import os.log

/// Session lifecycle state for clear status tracking
enum SessionState: Equatable {
    case idle
    case initializing  // Process launching, protocol init, waiting for session
    case ready  // Fully initialized, can send messages
    case closing
    case failed(String)

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    var isInitializing: Bool {
        if case .initializing = self { return true }
        return false
    }
}

/// ObservableObject that wraps ACPClient for managing an agent session
@MainActor
class AgentSession: ObservableObject, ACPClientDelegate {
    static let maxMessageCount = 500
    static let maxToolCallCount = 500
    // MARK: - Published Properties

    @Published var sessionId: SessionId?
    @Published var agentName: String
    @Published var workingDirectory: String

    // Tool calls stored in dictionary for O(1) lookup, with order array for chronological iteration
    @Published private(set) var toolCallsById: [String: ToolCall] = [:]
    @Published private(set) var toolCallOrder: [String] = []

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

    var acpClient: ACPClient?
    var cancellables = Set<AnyCancellable>()
    var process: Process?
    var notificationTask: Task<Void, Never>?
    var notificationProcessingTask: Task<Void, Never>?
    var versionCheckTask: Task<Void, Never>?
    let logger = Logger.forCategory("AgentSession")
    private var finalizeMessageTask: Task<Void, Never>?
    private var lastAgentChunkAt: Date?
    private static let finalizeIdleDelay: TimeInterval = 0.2
    private var isModeChanging = false
    private var thoughtBuffer: String = ""
    private var thoughtFlushTask: Task<Void, Never>?
    private static let thoughtUpdateInterval: TimeInterval = 0.06
    private var pendingAgentText: String = ""
    private var pendingAgentBlocks: [ContentBlock] = []
    private var agentMessageFlushTask: Task<Void, Never>?
    private static let agentMessageFlushInterval: TimeInterval = 0.0
    var pendingToolCallContentById: [String: [ToolCallContent]] = [:]
    var toolCallContentFlushTasks: [String: Task<Void, Never>] = [:]
    static let toolCallContentFlushInterval: TimeInterval = 0.25

    /// Currently pending Task tool calls (subagents) - used for parent tracking
    /// When only one Task is active, child tool calls are assigned to it
    /// When multiple Tasks are active (parallel), we cannot reliably assign parents
    var activeTaskIds: [String] = []
    /// Buffer tool call updates that arrive before the tool call itself
    var pendingToolCallUpdatesById: [String: [ToolCallUpdateDetails]] = [:]

    // Delegates
    private let fileSystemDelegate = AgentFileSystemDelegate()
    private let terminalDelegate = AgentTerminalDelegate()
    let permissionHandler = AgentPermissionHandler()
    private var agentCapabilities: AgentCapabilities?

    // MARK: - Initialization

    init(agentName: String = "", workingDirectory: String = "") {
        self.agentName = agentName
        self.workingDirectory = workingDirectory
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
    }

    private func scheduleThoughtFlush() {
        guard thoughtFlushTask == nil else { return }
        thoughtFlushTask = Task { @MainActor in
            defer { thoughtFlushTask = nil }
            try? await Task.sleep(for: .seconds(Self.thoughtUpdateInterval))
            currentThought = thoughtBuffer
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
        guard agentMessageFlushTask == nil else { return }
        agentMessageFlushTask = Task { @MainActor in
            defer { agentMessageFlushTask = nil }
            if Self.agentMessageFlushInterval > 0 {
                try? await Task.sleep(for: .seconds(Self.agentMessageFlushInterval))
            } else {
                await Task.yield()
            }
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
    func start(agentName: String, workingDir: String) async throws {
        // Atomically check and set active state to prevent race conditions
        guard !isActive && sessionState != .initializing else {
            throw AgentSessionError.sessionAlreadyActive
        }

        // Mark as initializing immediately for UI feedback
        sessionState = .initializing
        isActive = true

        let startTime = CFAbsoluteTimeGetCurrent()
        logger.info("[\(agentName)] Session start begin")

        // Store for potential rollback on error
        let previousAgentName = self.agentName
        let previousWorkingDir = self.workingDirectory

        self.agentName = agentName
        self.workingDirectory = workingDir

        // Get agent executable path from registry (nonisolated - no await needed)
        let agentPath = AgentRegistry.shared.getAgentPath(for: agentName)
        let isValid = AgentRegistry.shared.validateAgent(named: agentName)

        guard let agentPath = agentPath, isValid else {
            // Agent not configured or invalid - trigger setup dialog
            // Keep isActive true so UI shows the setup dialog
            needsAgentSetup = true
            missingAgentName = agentName
            setupError = nil
            sessionState = .failed("Agent not configured")
            return
        }

        // Initialize ACP client
        let client = ACPClient()
        self.acpClient = client

        // Set self as delegate
        await client.setDelegate(self)

        // Get launch arguments for this agent
        let launchArgs = AgentRegistry.shared.getAgentLaunchArgs(for: agentName)

        // Launch the agent process with correct working directory
        do {
            logger.info("[\(agentName)] Launching process...")
            try await client.launch(
                agentPath: agentPath, arguments: launchArgs, workingDirectory: workingDir)
            logger.info(
                "[\(agentName)] Process launched in \(String(format: "%.0f", (CFAbsoluteTimeGetCurrent() - startTime) * 1000))ms"
            )
        } catch {
            // Rollback on launch failure
            isActive = false
            sessionState = .failed(error.localizedDescription)
            self.agentName = previousAgentName
            self.workingDirectory = previousWorkingDir
            self.acpClient = nil
            logger.error("[\(agentName)] Launch failed: \(error.localizedDescription)")
            throw error
        }

        // Start notification listener BEFORE any protocol calls
        // This ensures we don't miss any notifications during initialization
        startNotificationListener(client: client)

        // Initialize protocol with timeout
        logger.info("[\(agentName)] Sending initialize request...")
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
                )
            )
            logger.info(
                "[\(agentName)] Initialize completed in \(String(format: "%.0f", (CFAbsoluteTimeGetCurrent() - startTime) * 1000))ms"
            )
        } catch {
            isActive = false
            sessionState = .failed("Initialize failed: \(error.localizedDescription)")
            self.acpClient = nil
            logger.error("[\(agentName)] Initialize failed: \(error.localizedDescription)")
            throw error
        }

        self.agentCapabilities = initResponse.agentCapabilities

        // Check agent version in background (non-blocking)
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

        if let authMethods = initResponse.authMethods, !authMethods.isEmpty {
            self.authMethods = authMethods

            // Check if we should skip authentication (previously succeeded without explicit auth)
            let shouldSkipAuth = AgentRegistry.shared.shouldSkipAuth(for: agentName)

            if shouldSkipAuth {
                // User has previously authenticated externally (e.g., claude /login)
                // Try session directly with normal timeout
                logger.info(
                    "[\(agentName)] Skipping auth (previously succeeded without explicit auth)...")
                do {
                    try await createSessionDirectly(workingDir: workingDir, client: client)
                    return
                } catch {
                    // Auth may have expired, clear skip preference and show dialog
                    logger.info(
                        "[\(agentName)] Session failed despite skip preference: \(error.localizedDescription)"
                    )
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
                    logger.error(
                        "Saved auth method '\(savedAuthMethod)' failed: \(error.localizedDescription)"
                    )
                    addSystemMessage(
                        "⚠️ Saved authentication method failed. Please re-authenticate.")
                    AgentRegistry.shared.clearAuthPreference(for: agentName)
                    // Fall through to show auth dialog
                }
            } else {
                // No saved preference - try session without auth first (user may have logged in externally)
                do {
                    logger.info("[\(agentName)] Trying session without auth first...")
                    try await createSessionDirectly(workingDir: workingDir, client: client)
                    // Success! Save skip preference for future sessions
                    AgentRegistry.shared.saveSkipAuth(for: agentName)
                    return
                } catch {
                    logger.info(
                        "[\(agentName)] Session without auth failed: \(error.localizedDescription)")
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
        logger.info("[\(agentName)] Creating new session...")
        let sessionResponse: NewSessionResponse
        do {
            let mcpServers = await resolveMCPServers()
            let sessionTimeout = effectiveSessionTimeout(mcpServers: mcpServers, defaultTimeout: 30.0)
            sessionResponse = try await client.newSession(
                workingDirectory: workingDir,
                mcpServers: mcpServers,
                timeout: sessionTimeout
            )
            logger.info(
                "[\(agentName)] Session created in \(String(format: "%.0f", (CFAbsoluteTimeGetCurrent() - startTime) * 1000))ms, sessionId: \(sessionResponse.sessionId.value)"
            )
        } catch {
            isActive = false
            sessionState = .failed("newSession failed: \(error.localizedDescription)")
            self.acpClient = nil
            logger.error("[\(agentName)] newSession failed: \(error.localizedDescription)")
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

        let metadata = AgentRegistry.shared.getMetadata(for: agentName)
        let displayName = metadata?.name ?? agentName
        AgentUsageStore.shared.recordSessionStart(agentId: agentName)
        addSystemMessage("Session started with \(displayName) in \(workingDir)")
    }

    func resolveMCPServers() async -> [MCPServerConfig] {
        let servers = await MCPConfigManager.shared.listServers(agentId: agentName)
        guard !servers.isEmpty else { return [] }

        let mcpCapabilities = agentCapabilities?.mcpCapabilities
        let allowHTTP = mcpCapabilities?.http == true
        let allowSSE = mcpCapabilities?.sse == true

        var configs: [MCPServerConfig] = []
        var skippedRemote: [String] = []
        for name in servers.keys.sorted() {
            guard let entry = servers[name] else { continue }
            switch entry.type {
            case "stdio":
                guard let command = entry.command else {
                    logger.warning("[\(self.agentName)] MCP server '\(name)' missing command")
                    continue
                }
                let env = (entry.env ?? [:]).sorted { $0.key < $1.key }.map { EnvVariable(name: $0.key, value: $0.value, _meta: nil) }
                let config = StdioServerConfig(
                    name: name,
                    command: command,
                    args: entry.args ?? [],
                    env: env,
                    _meta: nil
                )
                configs.append(.stdio(config))
            case "http":
                guard allowHTTP else {
                    skippedRemote.append(name)
                    logger.info("[\(self.agentName)] MCP server '\(name)' skipped (HTTP not supported)")
                    continue
                }
                guard let url = entry.url else {
                    logger.warning("[\(self.agentName)] MCP server '\(name)' missing url")
                    continue
                }
                let config = HTTPServerConfig(name: name, url: url, headers: [], _meta: nil)
                configs.append(.http(config))
            case "sse":
                guard allowSSE else {
                    skippedRemote.append(name)
                    logger.info("[\(self.agentName)] MCP server '\(name)' skipped (SSE not supported)")
                    continue
                }
                guard let url = entry.url else {
                    logger.warning("[\(self.agentName)] MCP server '\(name)' missing url")
                    continue
                }
                let config = SSEServerConfig(name: name, url: url, headers: [], _meta: nil)
                configs.append(.sse(config))
            default:
                logger.warning("[\(self.agentName)] MCP server '\(name)' has unknown type '\(entry.type)'")
            }
        }

        if !skippedRemote.isEmpty {
            let serverList = skippedRemote.joined(separator: ", ")
            await MainActor.run {
                if mcpCapabilities == nil {
                    addSystemMessage("⚠️ \(agentName) ACP did not advertise HTTP/SSE MCP support. Skipping remote MCP servers: \(serverList)")
                } else {
                    addSystemMessage("⚠️ \(agentName) does not support HTTP/SSE MCP servers. Skipping: \(serverList)")
                }
            }
        }

        return configs
    }

    func effectiveSessionTimeout(mcpServers: [MCPServerConfig], defaultTimeout: TimeInterval) -> TimeInterval {
        let hasRemote = mcpServers.contains { config in
            switch config {
            case .http, .sse:
                return true
            case .stdio:
                return false
            }
        }
        return hasRemote ? max(defaultTimeout, 180.0) : defaultTimeout
    }

    /// Set mode by ID
    func setModeById(_ modeId: String) async throws {
        logger.info("setModeById called: \(modeId) (current: \(self.currentModeId ?? "nil"))")

        // Skip if already on this mode or a change is in progress
        guard modeId != currentModeId, !isModeChanging else {
            logger.info("Skipping mode change: already on mode or change in progress")
            return
        }

        guard let sessionId = sessionId, let client = acpClient else {
            logger.error("setModeById failed: session not active")
            throw AgentSessionError.sessionNotActive
        }

        isModeChanging = true
        defer { isModeChanging = false }

        logger.info("Sending session/set_mode request...")
        let response = try await client.setMode(sessionId: sessionId, modeId: modeId)
        if response.success {
            logger.info("Mode change succeeded: \(modeId)")
            currentModeId = modeId
        } else {
            logger.warning("Mode change response indicated failure")
        }
    }

    /// Set model
    func setModel(_ modelId: String) async throws {
        guard let sessionId = sessionId, let client = acpClient else {
            throw AgentSessionError.sessionNotActive
        }

        let response = try await client.setModel(sessionId: sessionId, modelId: modelId)
        if response.success {
            currentModelId = modelId
            if let model = availableModels.first(where: { $0.modelId == modelId }) {
                addSystemMessage("Model changed to \(model.name)")
            } else {
                addSystemMessage("Model changed to \(modelId)")
            }
        }
    }

    /// Close the session
    func close() async {
        sessionState = .closing
        isActive = false

        // Cancel all background tasks
        notificationTask?.cancel()
        notificationTask = nil
        versionCheckTask?.cancel()
        versionCheckTask = nil

        if let client = acpClient {
            await client.terminate()
        }

        // Clean up delegates
        await terminalDelegate.cleanup()
        permissionHandler.cancelPendingRequest()

        acpClient = nil
        cancellables.removeAll()
        sessionState = .idle

        addSystemMessage("Session closed")
    }

    /// Retry starting the session after agent setup is completed
    func retryStart() async throws {
        // Clear error but keep needsAgentSetup true until start succeeds
        setupError = nil

        // Attempt to start session again
        try await start(agentName: agentName, workingDir: workingDirectory)

        // Only reset setup state after successful start
        needsAgentSetup = false
        missingAgentName = nil
    }

    // MARK: - ACPClientDelegate Methods

    // File operations are nonisolated to avoid blocking MainActor during large file I/O
    nonisolated func handleFileReadRequest(_ path: String, sessionId: String, line: Int?, limit: Int?)
        async throws -> ReadTextFileResponse
    {
        return try await fileSystemDelegate.handleFileReadRequest(
            path, sessionId: sessionId, line: line, limit: limit)
    }

    // File operations are nonisolated to avoid blocking MainActor during large file I/O
    nonisolated func handleFileWriteRequest(_ path: String, content: String, sessionId: String) async throws
        -> WriteTextFileResponse
    {
        return try await fileSystemDelegate.handleFileWriteRequest(
            path, content: content, sessionId: sessionId)
    }

    func handleTerminalCreate(
        command: String, sessionId: String, args: [String]?, cwd: String?, env: [EnvVariable]?,
        outputByteLimit: Int?
    ) async throws -> CreateTerminalResponse {
        // Fall back to session's working directory if cwd not specified
        let effectiveCwd = cwd ?? (workingDirectory.isEmpty ? nil : workingDirectory)

        return try await terminalDelegate.handleTerminalCreate(
            command: command,
            sessionId: sessionId,
            args: args,
            cwd: effectiveCwd,
            env: env,
            outputByteLimit: outputByteLimit
        )
    }

    func handleTerminalOutput(terminalId: TerminalId, sessionId: String) async throws
        -> TerminalOutputResponse
    {
        return try await terminalDelegate.handleTerminalOutput(
            terminalId: terminalId, sessionId: sessionId)
    }

    func handleTerminalWaitForExit(terminalId: TerminalId, sessionId: String) async throws
        -> WaitForExitResponse
    {
        return try await terminalDelegate.handleTerminalWaitForExit(
            terminalId: terminalId, sessionId: sessionId)
    }

    func handleTerminalKill(terminalId: TerminalId, sessionId: String) async throws
        -> KillTerminalResponse
    {
        return try await terminalDelegate.handleTerminalKill(
            terminalId: terminalId, sessionId: sessionId)
    }

    func handleTerminalRelease(terminalId: TerminalId, sessionId: String) async throws
        -> ReleaseTerminalResponse
    {
        return try await terminalDelegate.handleTerminalRelease(
            terminalId: terminalId, sessionId: sessionId)
    }

    func handlePermissionRequest(request: RequestPermissionRequest) async throws
        -> RequestPermissionResponse
    {
        return await permissionHandler.handlePermissionRequest(request: request)
    }

    /// Respond to a permission request - delegates to permission handler
    func respondToPermission(optionId: String) {
        permissionHandler.respondToPermission(optionId: optionId)
    }

    // MARK: - Terminal Output Access

    /// Get terminal output for display in UI
    func getTerminalOutput(terminalId: String) async -> String? {
        return await terminalDelegate.getOutput(terminalId: TerminalId(terminalId))
    }

    /// Check if terminal is still running
    func isTerminalRunning(terminalId: String) async -> Bool {
        return await terminalDelegate.isRunning(terminalId: TerminalId(terminalId))
    }

    // MARK: - Tool Call Management (O(1) Dictionary Operations)

    /// Get tool call by ID (O(1) lookup)
    func getToolCall(id: String) -> ToolCall? {
        toolCallsById[id]
    }

    /// Insert or update a tool call (O(1) operation)
    func upsertToolCall(_ toolCall: ToolCall) {
        let id = toolCall.toolCallId
        if toolCallsById[id] == nil {
            toolCallOrder.append(id)
        }
        toolCallsById[id] = toolCall
        trimToolCallsIfNeeded()
    }

    /// Update an existing tool call in place (O(1) operation)
    func updateToolCallInPlace(id: String, update: (inout ToolCall) -> Void) {
        guard var toolCall = toolCallsById[id] else { return }
        update(&toolCall)
        toolCallsById[id] = toolCall
    }

    /// Clear all tool calls
    func clearToolCalls() {
        toolCallsById.removeAll()
        toolCallOrder.removeAll()
        pendingToolCallUpdatesById.removeAll()
        pendingToolCallContentById.removeAll()
        for (_, task) in toolCallContentFlushTasks {
            task.cancel()
        }
        toolCallContentFlushTasks.removeAll()
    }

    private func trimToolCallsIfNeeded() {
        let excess = toolCallOrder.count - Self.maxToolCallCount
        guard excess > 0 else { return }
        let idsToRemove = toolCallOrder.prefix(excess)
        for id in idsToRemove {
            toolCallsById.removeValue(forKey: id)
        }
        toolCallOrder.removeFirst(excess)
    }

    func isAuthRequiredError(_ error: Error) -> Bool {
        if let acpError = error as? ACPClientError {
            if case .agentError(let jsonError) = acpError {
                if jsonError.code == -32000 { return true }
                let message = jsonError.message.lowercased()
                if message.contains("auth") && message.contains("required") { return true }
            }
        }

        let message = error.localizedDescription.lowercased()
        if message.contains("authentication required") || message.contains("auth required") {
            return true
        }
        if message.contains("not authenticated") {
            return true
        }
        return message.contains("unauthorized") || message.contains("401")
    }
}

// MARK: - Supporting Types

struct MessageItem: Identifiable, Equatable {
    let id: String
    let role: MessageRole
    let content: String
    let timestamp: Date
    var toolCalls: [ToolCall] = []
    var contentBlocks: [ContentBlock] = []
    var isComplete: Bool = false
    var startTime: Date?
    var executionTime: TimeInterval?
    var requestId: String?

    static func == (lhs: MessageItem, rhs: MessageItem) -> Bool {
        lhs.id == rhs.id && lhs.content == rhs.content && lhs.isComplete == rhs.isComplete
    }
}

enum MessageRole {
    case user
    case agent
    case system
}

enum AgentSessionError: LocalizedError {
    case sessionAlreadyActive
    case sessionNotActive
    case agentNotFound(String)
    case agentNotExecutable(String)
    case clientNotInitialized
    case custom(String)

    var errorDescription: String? {
        switch self {
        case .sessionAlreadyActive:
            return "Session is already active"
        case .sessionNotActive:
            return "No active session"
        case .agentNotFound(let name):
            return
                "Agent '\(name)' not configured. Please set the executable path in Settings → AI Agents, or click 'Auto Discover' to find it automatically."
        case .agentNotExecutable(let path):
            return "Agent at '\(path)' is not executable"
        case .clientNotInitialized:
            return "ACP client not initialized"
        case .custom(let message):
            return message
        }
    }
}
