//
//  AgentSessionAuth.swift
//  aizen
//
//  Authentication logic for AgentSession
//

import Foundation

// MARK: - AgentSession + Authentication

@MainActor
extension AgentSession {
    /// Helper to create session directly without authentication
    func createSessionDirectly(workingDir: String, client: ACPClient, timeout: TimeInterval = 60.0) async throws {
        logger.info("[\(self.agentName)] createSessionDirectly with timeout \(timeout)s...")
        let sessionResponse = try await client.newSession(
            workingDirectory: workingDir,
            mcpServers: [],
            timeout: timeout
        )
        logger.info("[\(self.agentName)] Session created, sessionId: \(sessionResponse.sessionId.value)")

        self.sessionId = sessionResponse.sessionId
        self.isActive = true
        self.sessionState = .ready

        if let modesInfo = sessionResponse.modes {
            self.availableModes = modesInfo.availableModes
            self.currentModeId = modesInfo.currentModeId
        }

        if let modelsInfo = sessionResponse.models {
            self.availableModels = modelsInfo.availableModels
            self.currentModelId = modelsInfo.currentModelId
        }

        // Start notification listener if not already started
        if notificationTask == nil {
            startNotificationListener(client: client)
        }
        let metadata = AgentRegistry.shared.getMetadata(for: agentName)
        let displayName = metadata?.name ?? agentName
        AgentUsageStore.shared.recordSessionStart(agentId: agentName)
        addSystemMessage("Session started with \(displayName) in \(workingDir)")
    }

    /// Helper to perform authentication and create session
    func performAuthentication(client: ACPClient, authMethodId: String, workingDir: String) async throws {
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

        AgentRegistry.shared.saveSkipAuth(for: agentName)

        needsAuthentication = false
        try await createSessionDirectly(workingDir: workingDirectory, client: client)
    }

    /// Authenticate with the agent
    func authenticate(authMethodId: String) async throws {
        guard let client = acpClient else {
            throw AgentSessionError.clientNotInitialized
        }

        AgentRegistry.shared.saveAuthPreference(agentName: agentName, authMethodId: authMethodId)

        try await performAuthentication(client: client, authMethodId: authMethodId, workingDir: workingDirectory)
    }
}
