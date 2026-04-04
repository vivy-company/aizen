//
//  MCPInstalledServer.swift
//  aizen
//
//  Represents an Aizen-managed MCP server attached to ACP sessions
//

import Foundation

struct MCPInstalledServer: Identifiable {
    let id: String
    let serverName: String
    let displayName: String
    let agentId: String
    let packageType: String?
    let transportType: String?
    let configuredEnv: [String: String]
    let configuredHeaders: [String: String]

    init(
        serverName: String,
        displayName: String,
        agentId: String,
        packageType: String? = nil,
        transportType: String? = nil,
        configuredEnv: [String: String] = [:],
        configuredHeaders: [String: String] = [:]
    ) {
        self.id = "\(agentId):\(serverName)"
        self.serverName = serverName
        self.displayName = displayName
        self.agentId = agentId
        self.packageType = packageType
        self.transportType = transportType
        self.configuredEnv = configuredEnv
        self.configuredHeaders = configuredHeaders
    }
}
