//
//  ChatAgentSession+Lifecycle.swift
//  aizen
//
//  Session start and resume lifecycle.
//

import ACP
import Combine
import CoreData
import Foundation
import UniformTypeIdentifiers

@MainActor
extension ChatAgentSession {
    // MARK: - Session Management

    func dismissSetupPrompt() {
        needsAgentSetup = false
        missingAgentName = nil
        setupError = nil
    }

    func retryStart() async throws {
        dismissSetupPrompt()
        try await start(
            agentName: agentName,
            workingDir: workingDirectory,
            chatSessionId: chatSessionId
        )
    }

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
