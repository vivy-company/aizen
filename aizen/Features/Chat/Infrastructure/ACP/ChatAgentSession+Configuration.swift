//
//  ChatAgentSession+Configuration.swift
//  aizen
//
//  Created by OpenAI Codex on 03.04.26.
//

import ACP
import Foundation

@MainActor
extension ChatAgentSession {
    func resolveMCPServers() async -> [MCPServerConfig] {
        let servers = await MCPServerStore.shared.servers(for: agentName, sessionId: chatSessionId)
        guard !servers.isEmpty else { return [] }

        let mcpCapabilities = agentCapabilities?.mcpCapabilities
        let allowHTTP = mcpCapabilities?.http == true
        let allowSSE = mcpCapabilities?.sse == true

        var configs: [MCPServerConfig] = []
        var skippedRemote: [String] = []
        var skippedACP: [String] = []

        for name in servers.keys.sorted() {
            guard let definition = servers[name] else { continue }
            let headers = (definition.headers ?? []).map { HTTPHeader(name: $0.name, value: $0.value, _meta: nil) }

            switch definition.transport {
            case .stdio:
                guard let command = definition.command else {
                    continue
                }
                let env = (definition.env ?? [:]).sorted { $0.key < $1.key }.map {
                    EnvVariable(name: $0.key, value: $0.value, _meta: nil)
                }
                let config = StdioServerConfig(
                    name: name,
                    command: command,
                    args: definition.args ?? [],
                    env: env,
                    _meta: nil
                )
                configs.append(.stdio(config))
            case .http:
                guard allowHTTP else {
                    skippedRemote.append(name)
                    continue
                }
                guard let url = definition.url else {
                    continue
                }
                let config = HTTPServerConfig(name: name, url: url, headers: headers, _meta: nil)
                configs.append(.http(config))
            case .sse:
                guard allowSSE else {
                    skippedRemote.append(name)
                    continue
                }
                guard let url = definition.url else {
                    continue
                }
                let config = SSEServerConfig(name: name, url: url, headers: headers, _meta: nil)
                configs.append(.sse(config))
            case .acp:
                skippedACP.append(name)
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

        if !skippedACP.isEmpty {
            let serverList = skippedACP.joined(separator: ", ")
            await MainActor.run {
                addSystemMessage(
                    "⚠️ Aizen has ACP-routed MCP servers configured, but the bundled ACP client only supports stdio/HTTP/SSE MCP transports today. Skipping: \(serverList)"
                )
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

    func setModeById(_ modeId: String) async throws {
        guard modeId != currentModeId, !isModeChanging else {
            return
        }

        guard let sessionId = sessionId, let client = acpClient else {
            throw AgentSessionError.sessionNotActive
        }

        isModeChanging = true
        defer { isModeChanging = false }

        _ = try await client.setMode(sessionId: sessionId, modeId: modeId)
        currentModeId = modeId
    }

    func setModel(_ modelId: String) async throws {
        guard let sessionId = sessionId, let client = acpClient else {
            throw AgentSessionError.sessionNotActive
        }

        _ = try await client.setModel(sessionId: sessionId, modelId: modelId)
        currentModelId = modelId
        if let model = availableModels.first(where: { $0.modelId == modelId }) {
            addSystemMessage("Model changed to \(model.name)")
        } else {
            addSystemMessage("Model changed to \(modelId)")
        }
    }

    func setConfigOption(configId: String, value: String) async throws {
        guard let sessionId = sessionId, let acpClient = acpClient else {
            throw AgentSessionError.sessionNotActive
        }

        let response = try await acpClient.setConfigOption(
            sessionId: sessionId,
            configId: SessionConfigId(configId),
            value: SessionConfigValueId(value)
        )

        availableConfigOptions = response.configOptions

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

    func setConfigOption(configId: String, value: Bool) async throws {
        guard let sessionId = sessionId, let acpClient = acpClient else {
            throw AgentSessionError.sessionNotActive
        }

        let response = try await acpClient.setConfigOption(
            sessionId: sessionId,
            configId: SessionConfigId(configId),
            value: value
        )

        availableConfigOptions = response.configOptions

        if let option = response.configOptions.first(where: { $0.id.value == configId }) {
            addSystemMessage("Config '\(option.name)' changed to '\(value ? "On" : "Off")'")
        }
    }
}
