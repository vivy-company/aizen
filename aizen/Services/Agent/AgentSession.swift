//
//  AgentSession.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import Foundation
import Combine
import UniformTypeIdentifiers

/// ObservableObject that wraps ACPClient for managing an agent session
@MainActor
class AgentSession: ObservableObject, ACPClientDelegate {
    // MARK: - Published Properties

    @Published var sessionId: SessionId?
    @Published var agentName: String
    @Published var workingDirectory: String
    @Published var toolCalls: [ToolCall] = []
    @Published var messages: [MessageItem] = []
    @Published var isActive: Bool = false
    @Published var currentThought: String?
    @Published var error: String?

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

    // MARK: - Private Properties

    private var acpClient: ACPClient?
    private var cancellables = Set<AnyCancellable>()
    private var process: Process?
    private var notificationTask: Task<Void, Never>?

    // Delegates
    private let fileSystemDelegate = AgentFileSystemDelegate()
    private let terminalDelegate = AgentTerminalDelegate()
    let permissionHandler = AgentPermissionHandler()

    // MARK: - Initialization

    init(agentName: String = "", workingDirectory: String = "") {
        self.agentName = agentName
        self.workingDirectory = workingDirectory
    }

    // MARK: - Session Management

    /// Start a new agent session
    func start(agentName: String, workingDir: String) async throws {
        guard !isActive else {
            throw AgentSessionError.sessionAlreadyActive
        }

        self.agentName = agentName
        self.workingDirectory = workingDir

        // Get agent executable path from registry
        guard let agentPath = await AgentRegistry.shared.getAgentPath(for: agentName),
              await AgentRegistry.shared.validateAgent(named: agentName) else {
            // Agent not configured or invalid - trigger setup dialog
            needsAgentSetup = true
            missingAgentName = agentName
            setupError = nil
            return
        }

        // Initialize ACP client
        let client = ACPClient()
        self.acpClient = client

        // Set self as delegate
        await client.setDelegate(self)

        // Get launch arguments for this agent
        let launchArgs = await AgentRegistry.shared.getAgentLaunchArgs(for: agentName)

        // Launch the agent process
        try await client.launch(agentPath: agentPath, arguments: launchArgs)

        // Initialize protocol
        let initResponse = try await client.initialize(
            protocolVersion: 1,
            capabilities: ClientCapabilities(
                fs: FileSystemCapabilities(
                    readTextFile: true,
                    writeTextFile: true
                ),
                terminal: true
            )
        )

        if let authMethods = initResponse.authMethods, !authMethods.isEmpty {
            self.authMethods = authMethods

            if let savedAuthMethod = await AgentRegistry.shared.getAuthPreference(for: agentName) {
                if savedAuthMethod == "skip" {
                    try await createSessionDirectly(workingDir: workingDir, client: client)
                    return
                } else {
                    do {
                        try await performAuthentication(client: client, authMethodId: savedAuthMethod, workingDir: workingDir)
                        return
                    } catch {
                        // Fall through to show auth dialog
                    }
                }
            }

            // No saved preference - show auth dialog
            self.needsAuthentication = true
            addSystemMessage("Authentication required for \(agentName). Available methods: \(authMethods.map { $0.name }.joined(separator: ", "))")
            return
        }

        // Create new session
        let sessionResponse = try await client.newSession(
            workingDirectory: workingDir,
            mcpServers: []
        )

        self.sessionId = sessionResponse.sessionId
        self.isActive = true

        if let modesInfo = sessionResponse.modes {
            self.availableModes = modesInfo.availableModes
            self.currentModeId = modesInfo.currentModeId
        }

        if let modelsInfo = sessionResponse.models {
            self.availableModels = modelsInfo.availableModels
            self.currentModelId = modelsInfo.currentModelId
        }

        startNotificationListener(client: client)

        let displayName = await AgentRegistry.shared.getMetadata(for: agentName)?.name ?? agentName
        addSystemMessage("Session started with \(displayName) in \(workingDir)")
    }

    /// Helper to create session directly
    private func createSessionDirectly(workingDir: String, client: ACPClient) async throws {
        let sessionResponse = try await client.newSession(
            workingDirectory: workingDir,
            mcpServers: []
        )

        self.sessionId = sessionResponse.sessionId
        self.isActive = true

        if let modesInfo = sessionResponse.modes {
            self.availableModes = modesInfo.availableModes
            self.currentModeId = modesInfo.currentModeId
        }

        if let modelsInfo = sessionResponse.models {
            self.availableModels = modelsInfo.availableModels
            self.currentModelId = modelsInfo.currentModelId
        }

        startNotificationListener(client: client)
        let displayName = await AgentRegistry.shared.getMetadata(for: agentName)?.name ?? agentName
        addSystemMessage("Session started with \(displayName) in \(workingDir)")
    }

    /// Helper to perform authentication and create session
    private func performAuthentication(client: ACPClient, authMethodId: String, workingDir: String) async throws {
        let authResponse = try await client.authenticate(
            authMethodId: authMethodId,
            credentials: nil
        )

        if !authResponse.success {
            throw NSError(domain: "AgentSession", code: -1, userInfo: [
                NSLocalizedDescriptionKey: authResponse.error ?? "Authentication failed"
            ])
        }

        needsAuthentication = false
        try await createSessionDirectly(workingDir: workingDir, client: client)
    }

    /// Create session without authentication (for when auth method doesn't work)
    func createSessionWithoutAuth() async throws {
        guard let client = acpClient else {
            throw AgentSessionError.clientNotInitialized
        }

        await AgentRegistry.shared.saveSkipAuth(for: agentName)

        needsAuthentication = false
        try await createSessionDirectly(workingDir: workingDirectory, client: client)
    }

    /// Authenticate with the agent
    func authenticate(authMethodId: String) async throws {
        guard let client = acpClient else {
            throw AgentSessionError.clientNotInitialized
        }

        await AgentRegistry.shared.saveAuthPreference(agentName: agentName, authMethodId: authMethodId)

        try await performAuthentication(client: client, authMethodId: authMethodId, workingDir: workingDirectory)
    }

    /// Send a message to the agent with optional file attachments
    func sendMessage(content: String, attachments: [URL] = []) async throws {
        guard let sessionId = sessionId, isActive else {
            throw AgentSessionError.sessionNotActive
        }

        guard let client = acpClient else {
            throw AgentSessionError.clientNotInitialized
        }

        // Clear tool calls from previous message
        toolCalls = []

        // Build content blocks array
        var contentBlocks: [ContentBlock] = []

        // Add text content
        contentBlocks.append(.text(TextContent(text: content)))

        // Add attachments as resource blocks
        for attachmentURL in attachments {
            if let resourceBlock = try? await createResourceBlock(from: attachmentURL) {
                contentBlocks.append(resourceBlock)
            }
        }

        // Add user message to UI with all content blocks
        addUserMessage(content, contentBlocks: contentBlocks)

        // Send to agent - notifications will arrive asynchronously
        // Tool calls will mark messages complete, or if no tools, the final chunk completes it
        let promptResponse = try await client.sendPrompt(sessionId: sessionId, content: contentBlocks)
    }

    /// Cancel the current prompt turn
    func cancelCurrentPrompt() async {
        guard let sessionId = sessionId, isActive else {
            return
        }

        guard let client = acpClient else {
            return
        }

        do {
            // Send cancel notification
            try await client.sendCancelNotification(sessionId: sessionId)

            // Add system message indicating cancellation
            let cancelMessage = MessageItem(
                id: UUID().uuidString,
                role: .system,
                content: "Agent stopped by user",
                timestamp: Date()
            )
            messages.append(cancelMessage)

            // Clear current thought
            currentThought = nil
        } catch {
            print("Error cancelling prompt: \(error)")
        }
    }

    /// Create a resource content block from a file URL
    private func createResourceBlock(from url: URL) async throws -> ContentBlock {
        // Ensure we can access the file
        guard url.startAccessingSecurityScopedResource() else {
            throw AgentSessionError.custom("Cannot access file: \(url.lastPathComponent)")
        }
        defer { url.stopAccessingSecurityScopedResource() }

        // Get MIME type
        let mimeType = getMimeType(for: url)

        // Determine if file is text or binary based on MIME type
        let isTextFile = mimeType?.hasPrefix("text/") ?? false ||
                        mimeType == "application/json" ||
                        mimeType == "application/xml" ||
                        mimeType == "application/javascript"

        if isTextFile {
            // Read as text
            let text = try String(contentsOf: url, encoding: .utf8)
            let resourceContent = ResourceContent(
                uri: url.absoluteString,
                mimeType: mimeType,
                text: text,
                blob: nil
            )
            return .resource(resourceContent)
        } else {
            // Read as binary and base64 encode
            let data = try Data(contentsOf: url)
            let base64 = data.base64EncodedString()
            let resourceContent = ResourceContent(
                uri: url.absoluteString,
                mimeType: mimeType,
                text: nil,
                blob: base64
            )
            return .resource(resourceContent)
        }
    }

    /// Get MIME type from file URL
    private func getMimeType(for url: URL) -> String? {
        if let utType = UTType(filenameExtension: url.pathExtension) {
            return utType.preferredMIMEType
        }
        return nil
    }

    /// Set mode by ID
    func setModeById(_ modeId: String) async throws {
        guard let sessionId = sessionId, let client = acpClient else {
            throw AgentSessionError.sessionNotActive
        }

        let response = try await client.setMode(sessionId: sessionId, modeId: modeId)
        if response.success {
            currentModeId = modeId
            if let modeName = availableModes.first(where: { $0.id == modeId })?.name {
                addSystemMessage("Mode changed to \(modeName)")
            }
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
        isActive = false

        // Cancel notification listener
        notificationTask?.cancel()
        notificationTask = nil

        if let client = acpClient {
            await client.terminate()
        }

        // Clean up delegates
        await terminalDelegate.cleanup()
        await permissionHandler.cancelPendingRequest()

        acpClient = nil
        cancellables.removeAll()

        addSystemMessage("Session closed")
    }

    // MARK: - Notification Handling

    private func startNotificationListener(client: ACPClient) {
        notificationTask = Task { @MainActor in
            for await notification in await client.notifications {
                handleNotification(notification)
            }
        }
    }

    private func handleNotification(_ notification: JSONRPCNotification) {
        guard notification.method == "session/update" else {
            return
        }

        do {
            let params = notification.params?.value as? [String: Any]
            let data = try JSONSerialization.data(withJSONObject: params ?? [:])
            let updateNotification = try JSONDecoder().decode(SessionUpdateNotification.self, from: data)

            let updateType = updateNotification.update.sessionUpdate

            // Handle different update types
            switch updateType {
            case "tool_call", "tool_call_update":
                // Tool call info is at the update level, not in an array
                if let toolCallId = updateNotification.update.toolCallId {
                    // If this is a new tool call (not an update), mark current message complete
                    // This creates a visual break between agent message and tool calls
              
                    if updateNotification.update.sessionUpdate == "tool_call" &&
                       !toolCalls.contains(where: { $0.toolCallId == toolCallId }) {
                        markLastMessageComplete()
                    }

                    // Check if this is an existing tool call
                    if let existingIndex = toolCalls.firstIndex(where: { $0.toolCallId == toolCallId }) {
                        // Update existing tool call with new fields
                        var updated = toolCalls[existingIndex]

                        if let status = updateNotification.update.status {
                            updated = ToolCall(
                                toolCallId: updated.toolCallId,
                                title: updateNotification.update.title ?? updated.title,
                                kind: updateNotification.update.kind ?? updated.kind,
                                status: status,
                                content: updated.content,
                                timestamp: updated.timestamp
                            )
                        }

                        toolCalls[existingIndex] = updated
                    } else if let title = updateNotification.update.title,
                              let kind = updateNotification.update.kind,
                              let status = updateNotification.update.status {
                        // New tool call
                        let toolCall = ToolCall(
                            toolCallId: toolCallId,
                            title: title,
                            kind: kind,
                            status: status,
                            content: [],
                            timestamp: Date()
                        )
                        toolCalls.append(toolCall)
                    }
                }

            case "agent_message_chunk":
                if let contentAny = updateNotification.update.content?.value {
                    currentThought = nil

                    if let contentDict = contentAny as? [String: Any],
                       let type = contentDict["type"] as? String,
                       type == "text",
                       let text = contentDict["text"] as? String {

                        // Append to last agent message if it exists and is still being streamed
                        if let lastMessage = messages.last,
                           lastMessage.role == .agent,
                           !lastMessage.isComplete {
                            let newContent = lastMessage.content + text
                            messages[messages.count - 1] = MessageItem(
                                id: lastMessage.id,
                                role: .agent,
                                content: newContent,
                                timestamp: lastMessage.timestamp,
                                toolCalls: lastMessage.toolCalls,
                                contentBlocks: lastMessage.contentBlocks,
                                isComplete: false,
                                startTime: lastMessage.startTime,
                                executionTime: lastMessage.executionTime,
                                requestId: lastMessage.requestId
                            )
                        } else {
                            // Start a new agent message
                            addAgentMessage(text, isComplete: false, startTime: Date())
                        }

                    }
                }

            case "user_message_chunk":
                // User messages already added when sending
                break

            case "agent_thought_chunk":
                if let contentAny = updateNotification.update.content?.value,
                   let contentDict = contentAny as? [String: Any],
                   let text = contentDict["text"] as? String {
                    print("Agent thought: \(text)")
                    // Accumulate thought chunks instead of replacing
                    if let existing = currentThought {
                        currentThought = existing + text
                    } else {
                        currentThought = text
                    }
                }

            case "plan":
                if let plan = updateNotification.update.plan {
                    agentPlan = plan
                }

            case "available_commands_update":
                if let commands = updateNotification.update.availableCommands {
                    availableCommands = commands
                }

            case "current_mode_update":
                if let mode = updateNotification.update.currentMode {
                    currentMode = mode
                }

            default:
                break
            }
        } catch {
            self.error = "Failed to parse session update: \(error.localizedDescription)"
        }
    }

    private func updateToolCalls(_ newToolCalls: [ToolCall]) {
        for newCall in newToolCalls {
            if let index = toolCalls.firstIndex(where: { $0.toolCallId == newCall.toolCallId }) {
                // Merge content instead of replacing entirely
                let existingContent = toolCalls[index].content
                let mergedContent = existingContent + newCall.content

                toolCalls[index] = ToolCall(
                    toolCallId: newCall.toolCallId,
                    title: newCall.title,
                    kind: newCall.kind,
                    status: newCall.status,
                    content: mergedContent
                )
            } else {
                toolCalls.append(newCall)
            }
        }
    }

    // MARK: - Message Management

    private func addUserMessage(_ content: String, contentBlocks: [ContentBlock] = []) {
        messages.append(MessageItem(
            id: UUID().uuidString,
            role: .user,
            content: content,
            timestamp: Date(),
            contentBlocks: contentBlocks
        ))
    }

    private func markLastMessageComplete() {
        if let lastIndex = messages.lastIndex(where: { $0.role == .agent && !$0.isComplete }) {
            let completedMessage = messages[lastIndex]
            let executionTime = completedMessage.startTime.map { Date().timeIntervalSince($0) }
            messages[lastIndex] = MessageItem(
                id: completedMessage.id,
                role: completedMessage.role,
                content: completedMessage.content,
                timestamp: completedMessage.timestamp,
                toolCalls: completedMessage.toolCalls,
                contentBlocks: completedMessage.contentBlocks,
                isComplete: true,
                startTime: completedMessage.startTime,
                executionTime: executionTime,
                requestId: completedMessage.requestId
            )
        }
    }

    private func addAgentMessage(_ content: String, toolCalls: [ToolCall] = [], isComplete: Bool = true, startTime: Date? = nil, requestId: String? = nil) {
        let newMessage = MessageItem(
            id: UUID().uuidString,
            role: .agent,
            content: content,
            timestamp: Date(),
            toolCalls: toolCalls,
            isComplete: isComplete,
            startTime: startTime,
            executionTime: nil,
            requestId: requestId
        )
        messages.append(newMessage)
    }

    private func addSystemMessage(_ content: String) {
        messages.append(MessageItem(
            id: UUID().uuidString,
            role: .system,
            content: content,
            timestamp: Date()
        ))
    }

    // MARK: - ACPClientDelegate Methods

    func handleFileReadRequest(_ path: String, startLine: Int?, endLine: Int?) async throws -> ReadTextFileResponse {
        return try await fileSystemDelegate.handleFileReadRequest(path, startLine: startLine, endLine: endLine)
    }

    func handleFileWriteRequest(_ path: String, content: String) async throws -> WriteTextFileResponse {
        return try await fileSystemDelegate.handleFileWriteRequest(path, content: content)
    }

    func handleTerminalCreate(command: String, args: [String]?, cwd: String?, env: [String: String]?, outputLimit: Int?) async throws -> CreateTerminalResponse {
        return try await terminalDelegate.handleTerminalCreate(
            command: command,
            args: args,
            cwd: cwd,
            env: env,
            outputLimit: outputLimit
        )
    }

    func handleTerminalOutput(terminalId: TerminalId) async throws -> TerminalOutputResponse {
        return try await terminalDelegate.handleTerminalOutput(terminalId: terminalId)
    }

    func handlePermissionRequest(request: RequestPermissionRequest) async throws -> RequestPermissionResponse {
        return await permissionHandler.handlePermissionRequest(request: request)
    }

    /// Respond to a permission request - delegates to permission handler
    func respondToPermission(optionId: String) {
        permissionHandler.respondToPermission(optionId: optionId)
    }

    /// Retry starting the session after agent setup is completed
    func retryStart() async throws {
        // Reset setup state
        needsAgentSetup = false
        missingAgentName = nil
        setupError = nil

        // Attempt to start session again
        try await start(agentName: agentName, workingDir: workingDirectory)
    }
}

// MARK: - Supporting Types

struct MessageItem: Identifiable {
    let id: String
    let role: MessageRole
    let content: String
    let timestamp: Date
    var toolCalls: [ToolCall] = []
    var contentBlocks: [ContentBlock] = []
    var isComplete: Bool = true
    var startTime: Date? // When agent started responding (first chunk)
    var executionTime: TimeInterval? // Time taken to generate response in seconds
    var requestId: String? // Track which user request this response belongs to
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
            return "Agent '\(name)' not configured. Please set the executable path in Settings → AI Agents, or click 'Auto Discover' to find it automatically."
        case .agentNotExecutable(let path):
            return "Agent at '\(path)' is not executable"
        case .clientNotInitialized:
            return "ACP client not initialized"
        case .custom(let message):
            return message
        }
    }
}
