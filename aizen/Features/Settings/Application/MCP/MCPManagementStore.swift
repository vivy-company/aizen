//
//  MCPManagementStore.swift
//  aizen
//
//  Stores Aizen-managed MCP server installation and sync state for settings UI.
//

import Combine
import Foundation

// MARK: - MCP Management Store

@MainActor
final class MCPManagementStore: ObservableObject {
    static let shared = MCPManagementStore()

    @Published var installedServers: [String: [MCPInstalledServer]] = [:]
    @Published var isSyncing: Set<String> = []
    @Published var isInstalling = false
    @Published var isRemoving = false

    let serverStore = MCPServerStore.shared

    private init() {}

    // MARK: - Support Check

    static func supportsMCPManagement(agentId: String) -> Bool {
        !agentId.isEmpty
    }

    // MARK: - Private Helpers

    func extractServerName(from fullName: String) -> String {
        if let lastComponent = fullName.split(separator: "/").last {
            return String(lastComponent)
        }
        return fullName
    }

    func runtimeCommand(for package: MCPPackage) -> (String, [String]) {
        var args: [String] = []

        switch package.registryType {
        case "npm":
            args.append("-y")
            args.append(package.identifier)
            if let runtimeArgs = package.runtimeArguments {
                args.append(contentsOf: runtimeArgs.flatMap { $0.toCommandLineArgs() })
            }
            return (package.runtimeHint, args)  // npx

        case "pypi":
            args.append(package.identifier)
            if let runtimeArgs = package.runtimeArguments {
                args.append(contentsOf: runtimeArgs.flatMap { $0.toCommandLineArgs() })
            }
            return (package.runtimeHint, args)  // uvx

        case "oci":
            args.append("run")
            args.append("-i")
            args.append("--rm")
            if let runtimeArgs = package.runtimeArguments {
                args.append(contentsOf: runtimeArgs.flatMap { $0.toCommandLineArgs() })
            }
            args.append(package.identifier)
            return ("docker", args)

        default:
            args.append(package.identifier)
            if let runtimeArgs = package.runtimeArguments {
                args.append(contentsOf: runtimeArgs.flatMap { $0.toCommandLineArgs() })
            }
            return (package.runtimeHint, args)
        }
    }
}
