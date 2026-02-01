//
//  AgentSession.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import Combine
import Foundation
import CoreData
import UniformTypeIdentifiers

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

    var acpClient: ACPClient?
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
    private var isModeChanging = false
    @Published var isResumingSession = false
    private var resumeReplayAgentMessages: [String] = []
    private var resumeReplayIndex: Int = 0
    private var resumeReplayBuffer: String = ""
    var suppressResumedAgentMessages = false
    var persistedToolCallIds: Set<String> = []
    private var thoughtBuffer: String = ""
    private var thoughtFlushTask: Task<Void, Never>?
    private static let thoughtUpdateInterval: TimeInterval = 0.06
    private var pendingAgentText: String = ""
    private var pendingAgentBlocks: [ContentBlock] = []
    private var agentMessageFlushTask: Task<Void, Never>?
    private static let agentMessageFlushInterval: TimeInterval = 0.0
    var pendingToolCallContentById: [String: [ToolCallContent]] = [:]
    var toolCallContentFlushTasks: [String: Task<Void, Never>] = [:]
    static let toolCallContentFlushInterval: TimeInterval = 0.1

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

        let client: ACPClient
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
        
        let client: ACPClient
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

    private func prepareResumeReplayState() {
        resumeReplayAgentMessages = messages
            .filter { $0.role == .agent }
            .map { $0.content }
        resumeReplayIndex = 0
        resumeReplayBuffer = ""
    }

    func clearResumeReplayState() {
        resumeReplayAgentMessages.removeAll()
        resumeReplayIndex = 0
        resumeReplayBuffer = ""
        suppressResumedAgentMessages = false
    }

    func shouldSkipResumedAgentChunk(text: String, hasContentBlocks: Bool) -> Bool {
        if suppressResumedAgentMessages {
            return true
        }
        guard isResumingSession else { return false }

        guard !text.isEmpty else {
            if hasContentBlocks {
                isResumingSession = false
                clearResumeReplayState()
                return false
            }
            return true
        }

        guard resumeReplayIndex < resumeReplayAgentMessages.count else {
            isResumingSession = false
            clearResumeReplayState()
            return false
        }

        let target = resumeReplayAgentMessages[resumeReplayIndex]
        let candidate = resumeReplayBuffer + text

        if target.hasPrefix(candidate) {
            resumeReplayBuffer = candidate
            if candidate == target {
                resumeReplayIndex += 1
                resumeReplayBuffer = ""
                if resumeReplayIndex >= resumeReplayAgentMessages.count {
                    isResumingSession = false
                    clearResumeReplayState()
                }
            }
            return true
        }

        isResumingSession = false
        clearResumeReplayState()
        return false
    }
    
    private func initializeClient(
        agentName: String,
        workingDir: String,
        startTime: CFAbsoluteTime,
        previousAgentName: String,
        previousWorkingDir: String
    ) async throws -> (client: ACPClient, initResponse: InitializeResponse) {
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
        let launchArgCandidates = launchArgCandidates(for: agentName, primary: launchArgs)
        var lastFailure: (stage: String, error: Error)?
        
        for (index, args) in launchArgCandidates.enumerated() {
            let isLastAttempt = index == launchArgCandidates.count - 1
            let client = ACPClient()
            await client.setDelegate(self)
            
            do {
                try await client.launch(
                    agentPath: agentPath,
                    arguments: args,
                    workingDirectory: workingDir
                )
            } catch {
                lastFailure = (stage: "launch", error: error)
                await client.terminate()
                if !isLastAttempt {
                    continue
                }
                break
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
                lastFailure = (stage: "initialize", error: error)
                await client.terminate()
                if !isLastAttempt {
                    continue
                }
                break
            }
            
            self.acpClient = client
            startNotificationListener(client: client)
            
            if args != launchArgs, var metadata = AgentRegistry.shared.getMetadata(for: agentName) {
                metadata.launchArgs = args
                await AgentRegistry.shared.updateAgent(metadata)
            }
            
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
        
        if let failure = lastFailure {
            isActive = false
            if failure.stage == "initialize" {
                sessionState = .failed("Initialize failed: \(failure.error.localizedDescription)")
            } else {
                sessionState = .failed(failure.error.localizedDescription)
            }
            self.agentName = previousAgentName
            self.workingDirectory = previousWorkingDir
            self.acpClient = nil
            throw failure.error
        }
        
        throw AgentSessionError.custom("Agent failed to start")
        
        
    }

    private func launchArgCandidates(for agentName: String, primary: [String]) -> [[String]] {
        var candidates: [[String]] = [primary]

        if agentName.lowercased() == "kimi" {
            let fallbacks = [["acp"], ["--acp"]]
            for args in fallbacks where !candidates.contains(where: { $0 == args }) {
                candidates.append(args)
            }
        }

        return candidates
    }
    
    func persistSessionId(chatSessionId: UUID) async throws {
        guard let sessionId = sessionId else {
            return
        }
        
        let context = PersistenceController.shared.container.viewContext
        
        try await SessionPersistenceService.shared.saveSessionId(
            sessionId.value,
            for: chatSessionId,
            in: context
        )
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
                    continue
                }
                guard let url = entry.url else {
                    continue
                }
                let config = HTTPServerConfig(name: name, url: url, headers: [], _meta: nil)
                configs.append(.http(config))
            case "sse":
                guard allowSSE else {
                    skippedRemote.append(name)
                    continue
                }
                guard let url = entry.url else {
                    continue
                }
                let config = SSEServerConfig(name: name, url: url, headers: [], _meta: nil)
                configs.append(.sse(config))
            default:
                break
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

        // Skip if already on this mode or a change is in progress
        guard modeId != currentModeId, !isModeChanging else {
            return
        }

        guard let sessionId = sessionId, let client = acpClient else {
            throw AgentSessionError.sessionNotActive
        }

        isModeChanging = true
        defer { isModeChanging = false }

        let response = try await client.setMode(sessionId: sessionId, modeId: modeId)
        if response.success {
            currentModeId = modeId
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

    /// Set config option
    func setConfigOption(configId: String, value: String) async throws {
        guard let sessionId = sessionId, let acpClient = acpClient else {
            throw AgentSessionError.sessionNotActive
        }

        let response = try await acpClient.setConfigOption(
            sessionId: sessionId,
            configId: SessionConfigId(configId),
            value: SessionConfigValueId(value)
        )

        self.availableConfigOptions = response.configOptions

        if let option = response.configOptions.first(where: { $0.id.value == configId }) {
            let optionName = option.name
            var valueName = value

            if case .select(let select) = option.kind {
                switch select.options {
                case .ungrouped(let options):
                    if let selectedOption = options.first(where: { $0.value.value == value }) {
                        valueName = selectedOption.name
                    }
                case .grouped(let groups):
                    for group in groups {
                        if let selectedOption = group.options.first(where: { $0.value.value == value }) {
                            valueName = selectedOption.name
                            break
                        }
                    }
                }
            }

            addSystemMessage("Config '\(optionName)' changed to '\(valueName)'")
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

        // Reset session state for retry - start() requires !isActive && sessionState != .initializing
        isActive = false
        sessionState = .idle

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
        let before = toolCall
        update(&toolCall)
        if toolCallChanged(before: before, after: toolCall) {
            toolCallsById[id] = toolCall
        }
    }

    private func toolCallChanged(before: ToolCall, after: ToolCall) -> Bool {
        if before.title != after.title { return true }
        if before.kind?.rawValue != after.kind?.rawValue { return true }
        if before.status != after.status { return true }
        if before.content.count != after.content.count { return true }
        if !toolCallLocationsEqual(before.locations, after.locations) { return true }

        let beforeLast = before.content.last?.displayText
        let afterLast = after.content.last?.displayText
        if beforeLast != afterLast { return true }

        if !anyCodableEqual(before.rawInput, after.rawInput) { return true }
        if !anyCodableEqual(before.rawOutput, after.rawOutput) { return true }

        return false
    }

    private func toolCallLocationsEqual(_ lhs: [ToolLocation]?, _ rhs: [ToolLocation]?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case (nil, _), (_, nil):
            return false
        case (let left?, let right?):
            guard left.count == right.count else { return false }
            for (l, r) in zip(left, right) {
                if l.path != r.path { return false }
                if l.line != r.line { return false }
            }
            return true
        }
    }

    private func anyCodableEqual(_ lhs: AnyCodable?, _ rhs: AnyCodable?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case (nil, _), (_, nil):
            return false
        case (let left?, let right?):
            return anyCodableSnapshot(left) == anyCodableSnapshot(right)
        }
    }

    private func anyCodableSnapshot(_ value: AnyCodable) -> String {
        let raw = value.value
        if let string = raw as? String { return "s:\(string)" }
        if let int = raw as? Int { return "i:\(int)" }
        if let double = raw as? Double { return "d:\(double)" }
        if let bool = raw as? Bool { return "b:\(bool)" }
        if raw is NSNull { return "null" }

        if JSONSerialization.isValidJSONObject(raw),
           let data = try? JSONSerialization.data(withJSONObject: raw, options: [.sortedKeys]),
           let json = String(data: data, encoding: .utf8) {
            return "j:\(json)"
        }

        return "d:\(String(describing: raw))"
    }

    /// Clear all tool calls
    func clearToolCalls() {
        toolCallsById.removeAll()
        toolCallOrder.removeAll()
        pendingToolCallUpdatesById.removeAll()
        pendingToolCallContentById.removeAll()
        persistedToolCallIds.removeAll()
        for (_, task) in toolCallContentFlushTasks {
            task.cancel()
        }
        toolCallContentFlushTasks.removeAll()
    }

    func loadPersistedToolCalls(_ toolCalls: [ToolCall]) {
        clearToolCalls()
        let sortedCalls = toolCalls.sorted { $0.timestamp < $1.timestamp }
        for call in sortedCalls {
            upsertToolCall(call)
            persistedToolCallIds.insert(call.toolCallId)
        }
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
        lhs.id == rhs.id &&
            lhs.content == rhs.content &&
            lhs.isComplete == rhs.isComplete &&
            lhs.contentBlocksSignature == rhs.contentBlocksSignature
    }

    private var contentBlocksSignature: (Int, String?) {
        let count = contentBlocks.count
        guard let last = contentBlocks.last else { return (count, nil) }
        let lastSignature: String
        switch last {
        case .text(let text):
            lastSignature = "text:\(text.text.count)"
        case .image(let image):
            lastSignature = "image:\(image.mimeType):\(image.data.count)"
        case .audio(let audio):
            lastSignature = "audio:\(audio.mimeType):\(audio.data.count)"
        case .resource(let resource):
            lastSignature = "resource:\(resource.resource.uri ?? ""):\(resource.resource.mimeType ?? "")"
        case .resourceLink(let link):
            lastSignature = "link:\(link.uri)"
        }
        return (count, lastSignature)
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
    case sessionResumeUnsupported
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
        case .sessionResumeUnsupported:
            return "Agent does not support session resume"
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
