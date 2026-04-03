//
//  ChatAgentSession+StartupSupport.swift
//  aizen
//
//  Created by OpenAI Codex on 03.04.26.
//

import ACP
import CoreData
import Foundation

@MainActor
extension ChatAgentSession {
    func initializeClient(
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
            acpClient = nil
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
            acpClient = nil
            throw error
        }

        acpClient = client
        startNotificationListener(client: client)
        agentCapabilities = initResponse.agentCapabilities

        versionCheckTask = Task { [weak self] in
            guard let self else { return }
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
        guard let sessionId else {
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
