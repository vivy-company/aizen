//
//  ChatAgentSessionAuth.swift
//  aizen
//
//  Authentication logic for ChatAgentSession
//

import ACP
import Foundation

// MARK: - ChatAgentSession + Authentication

@MainActor
extension ChatAgentSession {
    func isAuthRequiredError(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("auth") ||
            message.contains("api key") ||
            message.contains("unauthorized") ||
            message.contains("401") ||
            message.contains("forbidden") ||
            message.contains("login")
    }

    func handleAuthenticationHandshake(
        authMethods: [AuthMethod],
        agentName: String,
        workingDir: String,
        client: Client
    ) async throws -> Bool {
        self.authMethods = authMethods

        let shouldSkipAuth = AgentRegistry.shared.shouldSkipAuth(for: agentName)

        if shouldSkipAuth {
            do {
                try await createSessionDirectly(workingDir: workingDir, client: client)
                return true
            } catch {
                AgentRegistry.shared.clearAuthPreference(for: agentName)
            }
        } else if let savedAuthMethod = AgentRegistry.shared.getAuthPreference(for: agentName) {
            do {
                try await performAuthentication(
                    client: client,
                    authMethodId: savedAuthMethod,
                    workingDir: workingDir
                )
                return true
            } catch {
                addSystemMessage("⚠️ Saved authentication method failed. Please re-authenticate.")
                AgentRegistry.shared.clearAuthPreference(for: agentName)
            }
        } else {
            do {
                try await createSessionDirectly(workingDir: workingDir, client: client)
                AgentRegistry.shared.saveSkipAuth(for: agentName)
                return true
            } catch {
                let errorMessage = error.localizedDescription.lowercased()
                if isAuthRequiredError(error) {
                    needsAuthentication = true
                    if errorMessage.contains("api key") || errorMessage.contains("invalid") ||
                        errorMessage.contains("unauthorized") || errorMessage.contains("401") {
                        addSystemMessage("⚠️ \(error.localizedDescription)")
                    } else {
                        addSystemMessage("Authentication required. Use the login button or configure API keys in environment variables.")
                    }
                    return true
                }
            }
        }

        needsAuthentication = true
        addSystemMessage("Authentication required. Use the login button or configure API keys in environment variables.")
        return false
    }

    /// Helper to create session directly without authentication
    func createSessionDirectly(workingDir: String, client: Client, timeout: TimeInterval = 60.0) async throws {
        let mcpServers = await resolveMCPServers()
        let sessionTimeout = effectiveSessionTimeout(mcpServers: mcpServers, defaultTimeout: timeout)
        let sessionResponse = try await client.newSession(
            workingDirectory: workingDir,
            mcpServers: mcpServers,
            timeout: sessionTimeout
        )

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
        
        if let configOptions = sessionResponse.configOptions {
            self.availableConfigOptions = configOptions
        }

        // Start notification listener if not already started
        if notificationTask == nil {
            startNotificationListener(client: client)
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

    /// Helper to perform authentication and create session
    func performAuthentication(client: Client, authMethodId: String, workingDir: String) async throws {
        let authResponse = try await client.authenticate(
            authMethodId: authMethodId,
            credentials: nil
        )

        if !authResponse.success {
            throw NSError(domain: "ChatAgentSession", code: -1, userInfo: [
                NSLocalizedDescriptionKey: authResponse.error ?? "Authentication failed"
            ])
        }

        try await createSessionDirectly(workingDir: workingDir, client: client)
        needsAuthentication = false
    }

    /// Create session without authentication (for when auth method doesn't work)
    func createSessionWithoutAuth() async throws {
        guard let client = acpClient else {
            throw AgentSessionError.clientNotInitialized
        }

        try await createSessionDirectly(workingDir: workingDirectory, client: client)
        AgentRegistry.shared.saveSkipAuth(for: agentName)
        needsAuthentication = false
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
