//
//  ChatAgentSession+SessionState.swift
//  aizen
//
//  Created by OpenAI Codex on 03.04.26.
//

import ACP
import Foundation

@MainActor
extension ChatAgentSession {
    func applySessionState(from response: NewSessionResponse) {
        sessionId = response.sessionId
        sessionState = .ready

        if let modesInfo = response.modes {
            availableModes = modesInfo.availableModes
            currentModeId = modesInfo.currentModeId
        }

        if let modelsInfo = response.models {
            availableModels = modelsInfo.availableModels
            currentModelId = modelsInfo.currentModelId
        }

        if let configOptions = response.configOptions {
            availableConfigOptions = configOptions
        }
    }

    func applySessionState(from response: LoadSessionResponse) {
        sessionId = response.sessionId
        sessionState = .ready

        if let modesInfo = response.modes {
            availableModes = modesInfo.availableModes
            currentModeId = modesInfo.currentModeId
        }

        if let modelsInfo = response.models {
            availableModels = modelsInfo.availableModels
            currentModelId = modelsInfo.currentModelId
        }

        if let configOptions = response.configOptions {
            availableConfigOptions = configOptions
        }
    }

    func announceSessionStart(agentName: String, workingDir: String) {
        let displayName = AgentRegistry.shared.getMetadata(for: agentName)?.name ?? agentName
        AgentUsageStore.shared.recordSessionStart(agentId: agentName)
        addSystemMessage("Session started with \(displayName) in \(workingDir)")
    }

    func announceSessionResume(agentName: String, workingDir: String) {
        let displayName = AgentRegistry.shared.getMetadata(for: agentName)?.name ?? agentName
        AgentUsageStore.shared.recordSessionStart(agentId: agentName)
        addSystemMessage("Session resumed with \(displayName) in \(workingDir)")
    }
}
