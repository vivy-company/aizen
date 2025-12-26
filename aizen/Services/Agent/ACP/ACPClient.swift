//
//  ACPClient.swift
//  aizen
//
//  Actor-based ACP agent subprocess manager
//

import Foundation
import os.log

// ACPClientDelegate is defined in ACPRequestRouter
typealias ACPClientDelegate = ACPRequestDelegate

// MARK: - Debug Message Types

enum DebugMessageDirection {
    case outgoing
    case incoming
}

struct DebugMessage {
    let direction: DebugMessageDirection
    let timestamp: Date
    let rawData: Data
    let method: String?

    var jsonString: String? {
        String(data: rawData, encoding: .utf8)
    }
}

actor ACPClient {
    // MARK: - Properties

    private let logger = Logger.forCategory("ACPClient")

    private let processManager: ACPProcessManager
    private let requestRouter: ACPRequestRouter
    private let errorHandler: ACPErrorHandler

    private var pendingRequests: [RequestId: CheckedContinuation<JSONRPCResponse, Error>] = [:]
    private var nextRequestId: Int = 1

    private let notificationContinuation: AsyncStream<JSONRPCNotification>.Continuation
    private let notificationStream: AsyncStream<JSONRPCNotification>

    private var debugContinuation: AsyncStream<DebugMessage>.Continuation?
    private var debugStream: AsyncStream<DebugMessage>?

    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    weak var delegate: ACPClientDelegate?

    // MARK: - Initialization

    init() {
        // Set up JSON decoder/encoder
        // Note: We manually handle camelCase/snake_case in CodingKeys where needed
        decoder = JSONDecoder()
        encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]

        // Create notification stream
        var continuation: AsyncStream<JSONRPCNotification>.Continuation!
        notificationStream = AsyncStream { cont in
            continuation = cont
        }
        notificationContinuation = continuation

        // Initialize components
        processManager = ACPProcessManager(encoder: encoder, decoder: decoder)
        requestRouter = ACPRequestRouter(encoder: encoder, decoder: decoder)
        errorHandler = ACPErrorHandler(encoder: encoder)

        // Set up callbacks
        Task {
            await processManager.setDataReceivedCallback { [weak self] data in
                await self?.handleMessage(data: data)
            }
            await processManager.setTerminationCallback { [weak self] exitCode in
                await self?.handleTermination(exitCode: exitCode)
            }
        }
    }

    // MARK: - Public API

    var notifications: AsyncStream<JSONRPCNotification> {
        notificationStream
    }

    var debugMessages: AsyncStream<DebugMessage>? {
        debugStream
    }

    func enableDebugStream() {
        guard debugStream == nil else { return }
        var continuation: AsyncStream<DebugMessage>.Continuation!
        debugStream = AsyncStream { cont in
            continuation = cont
        }
        debugContinuation = continuation
    }

    func disableDebugStream() {
        debugContinuation?.finish()
        debugContinuation = nil
        debugStream = nil
    }

    func setDelegate(_ delegate: ACPClientDelegate?) {
        self.delegate = delegate
        Task {
            await requestRouter.setDelegate(delegate)
        }
    }

    func launch(agentPath: String, arguments: [String] = [], workingDirectory: String? = nil) async throws {
        try await processManager.launch(agentPath: agentPath, arguments: arguments, workingDirectory: workingDirectory)
    }

    func initialize(
        protocolVersion: Int = 1,
        capabilities: ClientCapabilities,
        clientInfo: ClientInfo? = nil,
        timeout: TimeInterval = 30.0
    ) async throws -> InitializeResponse {
        // Use provided clientInfo or default Aizen info
        let info = clientInfo ?? ClientInfo(
            name: "Aizen",
            title: "Aizen",
            version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        )

        let request = InitializeRequest(
            protocolVersion: protocolVersion,
            clientCapabilities: capabilities,
            clientInfo: info
        )

        let response = try await sendRequest(method: "initialize", params: request, timeout: timeout)

        guard let result = response.result else {
            if let error = response.error {
                throw ACPClientError.agentError(error)
            }
            throw ACPClientError.invalidResponse
        }

        let data = try encoder.encode(result)
        return try decoder.decode(InitializeResponse.self, from: data)
    }

    func newSession(
        workingDirectory: String,
        mcpServers: [MCPServerConfig] = [],
        timeout: TimeInterval = 30.0
    ) async throws -> NewSessionResponse {
        let request = NewSessionRequest(
            cwd: workingDirectory,
            mcpServers: mcpServers
        )

        let response = try await sendRequest(method: "session/new", params: request, timeout: timeout)

        guard let result = response.result else {
            if let error = response.error {
                throw ACPClientError.agentError(error)
            }
            throw ACPClientError.invalidResponse
        }

        let data = try encoder.encode(result)
        return try decoder.decode(NewSessionResponse.self, from: data)
    }

    func sendPrompt(
        sessionId: SessionId,
        content: [ContentBlock]
    ) async throws -> SessionPromptResponse {
        let request = SessionPromptRequest(
            sessionId: sessionId,
            prompt: content
        )

        // No timeout for prompts - agent can run for hours
        let response = try await sendRequest(method: "session/prompt", params: request, timeout: nil)

        if let error = response.error {
            throw ACPClientError.agentError(error)
        }

        guard let result = response.result else {
            throw ACPClientError.invalidResponse
        }

        let data = try encoder.encode(result)
        return try decoder.decode(SessionPromptResponse.self, from: data)
    }

    func authenticate(
        authMethodId: String,
        credentials: [String: String]? = nil
    ) async throws -> AuthenticateResponse {
        let request = AuthenticateRequest(
            methodId: authMethodId,
            credentials: credentials
        )

        let response = try await sendRequest(method: "authenticate", params: request)

        // Check for errors first
        if let error = response.error {
            throw ACPClientError.agentError(error)
        }

        // For authenticate, null or empty object result means success
        if response.result == nil || (response.result?.value is NSNull) {
            return AuthenticateResponse(success: true, error: nil)
        }

        // Check for empty object (Codex returns {})
        if let dict = response.result?.value as? [String: Any], dict.isEmpty {
            return AuthenticateResponse(success: true, error: nil)
        }

        // Otherwise try to decode the result
        guard let result = response.result else {
            throw ACPClientError.invalidResponse
        }

        do {
            let data = try encoder.encode(result)
            return try decoder.decode(AuthenticateResponse.self, from: data)
        } catch {
            // If decoding fails but there's no error, treat as success
            return AuthenticateResponse(success: true, error: nil)
        }
    }

    func setMode(
        sessionId: SessionId,
        modeId: String
    ) async throws -> SetModeResponse {
        let request = SetModeRequest(
            sessionId: sessionId,
            modeId: modeId
        )

        let response = try await sendRequest(method: "session/set_mode", params: request)

        // Check for errors
        if let error = response.error {
            throw ACPClientError.agentError(error)
        }

        // Empty object or null = success
        return SetModeResponse(success: true)
    }

    func setModel(
        sessionId: SessionId,
        modelId: String
    ) async throws -> SetModelResponse {
        let request = SetModelRequest(
            sessionId: sessionId,
            modelId: modelId
        )

        let response = try await sendRequest(method: "session/set_model", params: request)

        // Check for errors
        if let error = response.error {
            throw ACPClientError.agentError(error)
        }

        // Empty object or null = success
        return SetModelResponse(success: true)
    }

    func cancelSession(sessionId: SessionId) async throws {
        // session/cancel is a notification per ACP spec (no response expected)
        try await sendCancelNotification(sessionId: sessionId)
    }

    func loadSession(
        sessionId: SessionId,
        cwd: String? = nil,
        mcpServers: [MCPServerConfig]? = nil
    ) async throws -> LoadSessionResponse {
        let request = LoadSessionRequest(
            sessionId: sessionId,
            cwd: cwd,
            mcpServers: mcpServers
        )

        let response = try await sendRequest(method: "session/load", params: request)

        guard let result = response.result else {
            if let error = response.error {
                throw ACPClientError.agentError(error)
            }
            throw ACPClientError.invalidResponse
        }

        let data = try encoder.encode(result)
        return try decoder.decode(LoadSessionResponse.self, from: data)
    }

    func sendRequest<T: Encodable>(
        method: String,
        params: T,
        timeout: TimeInterval? = 120.0
    ) async throws -> JSONRPCResponse {
        guard await processManager.isRunning() else {
            throw ACPClientError.processNotRunning
        }

        let requestId = RequestId.number(nextRequestId)
        nextRequestId += 1

        let paramsData = try encoder.encode(params)
        let paramsValue = try decoder.decode(AnyCodable.self, from: paramsData)

        let request = JSONRPCRequest(
            id: requestId,
            method: method,
            params: paramsValue
        )

        return try await withRequestTimeout(seconds: timeout, requestId: requestId) {
            try await withCheckedThrowingContinuation { continuation in
                Task {
                    await self.registerRequest(id: requestId, continuation: continuation)

                    do {
                        try await self.writeMessageWithDebug(request, method: method)
                    } catch {
                        await self.failRequest(id: requestId, error: error)
                    }
                }
            }
        }
    }

    private func withRequestTimeout<T>(
        seconds: TimeInterval?,
        requestId: RequestId,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        // No timeout - just run the operation directly
        guard let seconds = seconds else {
            return try await operation()
        }

        do {
            return try await withThrowingTaskGroup(of: T.self) { group in
                group.addTask {
                    try await operation()
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                    throw ACPClientError.requestTimeout
                }

                guard let result = try await group.next() else {
                    throw ACPClientError.requestTimeout
                }
                group.cancelAll()
                return result
            }
        } catch is ACPClientError {
            // Clean up pending request on timeout
            pendingRequests.removeValue(forKey: requestId)
            throw ACPClientError.requestTimeout
        }
    }

    func sendCancelNotification(sessionId: SessionId) async throws {
        guard await processManager.isRunning() else {
            throw ACPClientError.processNotRunning
        }

        struct CancelParams: Encodable {
            let sessionId: SessionId
        }

        let params = CancelParams(sessionId: sessionId)
        let paramsData = try encoder.encode(params)
        let paramsValue = try decoder.decode(AnyCodable.self, from: paramsData)

        let notification = JSONRPCNotification(
            method: "session/cancel",
            params: paramsValue
        )

        try await writeMessageWithDebug(notification, method: "session/cancel")
    }

    func terminate() async {
        await processManager.terminate()

        // Fail all pending requests
        for (_, continuation) in pendingRequests {
            continuation.resume(throwing: ACPClientError.processNotRunning)
        }
        pendingRequests.removeAll()

        notificationContinuation.finish()
        debugContinuation?.finish()
        debugContinuation = nil
        debugStream = nil
    }

    // MARK: - Private Methods

    private func handleMessage(data: Data) async {
        // Skip empty or whitespace-only lines
        guard let text = String(data: data, encoding: .utf8),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        // Emit to debug stream if enabled
        if let continuation = debugContinuation {
            let method = extractMethod(from: data)
            continuation.yield(DebugMessage(
                direction: .incoming,
                timestamp: Date(),
                rawData: data,
                method: method
            ))
        }

        do {
            let message = try decoder.decode(ACPMessage.self, from: data)

            switch message {
            case .response(let response):
                await handleResponse(response)

            case .notification(let notification):
                // Notification logs were too verbose; keep only decode failures
                notificationContinuation.yield(notification)

            case .request(let request):
                await handleIncomingRequest(request)
            }
        } catch {
            // Log at debug level - non-JSON output from agent (debug messages, status lines, etc.)
            if let text = String(data: data, encoding: .utf8) {
                logger.debug("Non-JSON output from agent: \(text.prefix(200))")
            }
        }
    }

    private func handleResponse(_ response: JSONRPCResponse) async {
        guard let continuation = pendingRequests.removeValue(forKey: response.id) else {
            return
        }

        continuation.resume(returning: response)
    }

    private func handleIncomingRequest(_ request: JSONRPCRequest) async {
        logger.info("Incoming request: \(request.method) id=\(request.id)")
        do {
            let response = try await requestRouter.routeRequest(request)
            logger.info("Request \(request.method) succeeded")
            try await sendSuccessResponse(requestId: request.id, result: response)
        } catch {
            logger.error("Error handling request \(request.method): \(error.localizedDescription)")

            if let acpError = error as? ACPClientError, case .invalidResponse = acpError {
                try? await sendErrorResponse(
                    requestId: request.id,
                    code: -32601,
                    message: "Method not found: \(request.method)"
                )
            } else {
                try? await sendErrorResponse(
                    requestId: request.id,
                    code: -32603,
                    message: "Internal error: \(error.localizedDescription)"
                )
            }
        }
    }

    private func sendSuccessResponse(requestId: RequestId, result: AnyCodable) async throws {
        let response = JSONRPCResponse(id: requestId, result: result, error: nil)
        try await writeMessageWithDebug(response, method: nil)
    }

    private func sendErrorResponse(requestId: RequestId, code: Int, message: String) async throws {
        let errorResponse = try await errorHandler.createErrorResponse(
            requestId: requestId,
            code: code,
            message: message
        )
        try await writeMessageWithDebug(errorResponse, method: nil)
    }

    private func handleTermination(exitCode: Int32) async {
        logger.info("Agent process terminated with code: \(exitCode)")

        // Fail all pending requests
        for (_, continuation) in pendingRequests {
            continuation.resume(throwing: ACPClientError.processFailed(exitCode))
        }
        pendingRequests.removeAll()

        notificationContinuation.finish()
    }

    private func registerRequest(
        id: RequestId,
        continuation: CheckedContinuation<JSONRPCResponse, Error>
    ) async {
        pendingRequests[id] = continuation
    }

    private func failRequest(id: RequestId, error: Error) async {
        if let continuation = pendingRequests.removeValue(forKey: id) {
            continuation.resume(throwing: error)
        }
    }

    private func requestIdDescription(_ id: RequestId) -> String {
        switch id {
        case .number(let num): return String(num)
        case .string(let str): return str
        }
    }

    private func describeMessage(_ message: ACPMessage) -> String {
        switch message {
        case .request(let request):
            return "request \(request.method) [id: \(requestIdDescription(request.id))]"
        case .response(let response):
            return "response [id: \(requestIdDescription(response.id))]"
        case .notification(let notification):
            return "notification \(notification.method)"
        }
    }

    private func extractMethod(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json["method"] as? String
    }

    private func writeMessageWithDebug<T: Encodable>(_ message: T, method: String? = nil) async throws {
        // Emit to debug stream if enabled
        if let continuation = debugContinuation {
            if let data = try? encoder.encode(message) {
                continuation.yield(DebugMessage(
                    direction: .outgoing,
                    timestamp: Date(),
                    rawData: data,
                    method: method
                ))
            }
        }
        try await processManager.writeMessage(message)
    }
}
