//
//  ChatAgentSession+Lifecycle.swift
//  aizen
//
//  Created by OpenAI Codex on 03.04.26.
//

import ACP
import Foundation

@MainActor
extension ChatAgentSession {
    func close() async {
        sessionState = .closing
        isActive = false

        notificationTask?.cancel()
        notificationTask = nil
        versionCheckTask?.cancel()
        versionCheckTask = nil

        if let client = acpClient {
            await client.terminate()
        }

        await terminalDelegate.cleanup()
        permissionHandler.cancelPendingRequest()

        acpClient = nil
        cancellables.removeAll()
        sessionState = .idle

        addSystemMessage("Session closed")
    }

    func retryStart() async throws {
        setupError = nil
        isActive = false
        sessionState = .idle

        try await start(agentName: agentName, workingDir: workingDirectory)

        needsAgentSetup = false
        missingAgentName = nil
    }

    func dismissSetupPrompt() {
        needsAgentSetup = false
        setupError = nil
    }

    func isAuthRequiredError(_ error: Error) -> Bool {
        if let acpError = error as? ClientError {
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
