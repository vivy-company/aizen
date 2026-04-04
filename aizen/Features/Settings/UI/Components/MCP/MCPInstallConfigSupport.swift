//
//  MCPInstallConfigSupport.swift
//  aizen
//
//  Created by OpenAI Codex on 05.04.26.
//

import SwiftUI

enum MCPInstallConfigSupport {
    static func setupInitialState(
        hasPackages: Bool,
        hasRemotes: Bool,
        selectedPackage: MCPPackage?,
        installType: inout MCPInstallConfigSheet.InstallType,
        envValues: inout [String: String]
    ) {
        if !hasPackages && hasRemotes {
            installType = .remote
        }

        if let package = selectedPackage {
            for envVar in package.environmentVariables ?? [] {
                if let defaultValue = envVar.default {
                    envValues[envVar.name] = defaultValue
                }
            }
        }
    }

    static func install(
        manager: MCPManagementStore,
        installType: MCPInstallConfigSheet.InstallType,
        server: MCPServer,
        agentId: String,
        selectedPackage: MCPPackage?,
        selectedRemote: MCPRemote?,
        envValues: [String: String]
    ) async throws {
        if installType == .package, let package = selectedPackage {
            try await manager.installPackage(
                server: server,
                package: package,
                agentId: agentId,
                env: envValues.filter { !$0.value.isEmpty }
            )
        } else if installType == .remote, let remote = selectedRemote {
            try await manager.installRemote(
                server: server,
                remote: remote,
                agentId: agentId,
                env: [:]
            )
        }
    }
}
