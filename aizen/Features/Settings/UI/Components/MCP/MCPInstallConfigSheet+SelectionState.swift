//
//  MCPInstallConfigSheet+SelectionState.swift
//  aizen
//
//  Selection and environment state helpers for MCP installation
//

import SwiftUI

extension MCPInstallConfigSheet {
    enum InstallType: String, CaseIterable {
        case package = "Package"
        case remote = "Remote"
    }

    var hasPackages: Bool {
        server.packages != nil && !server.packages!.isEmpty
    }

    var hasRemotes: Bool {
        server.remotes != nil && !server.remotes!.isEmpty
    }

    var selectedPackage: MCPPackage? {
        guard hasPackages, selectedPackageIndex < server.packages!.count else { return nil }
        return server.packages![selectedPackageIndex]
    }

    var selectedRemote: MCPRemote? {
        guard hasRemotes, selectedRemoteIndex < server.remotes!.count else { return nil }
        return server.remotes![selectedRemoteIndex]
    }

    var requiredEnvVars: [MCPEnvVar] {
        if installType == .package, let package = selectedPackage {
            return package.environmentVariables?.filter { $0.required } ?? []
        }
        return []
    }

    var optionalEnvVars: [MCPEnvVar] {
        if installType == .package, let package = selectedPackage {
            return package.environmentVariables?.filter { !$0.required } ?? []
        }
        return []
    }

    var canInstall: Bool {
        for envVar in requiredEnvVars {
            let value = envValues[envVar.name] ?? ""
            if value.trimmingCharacters(in: .whitespaces).isEmpty {
                return false
            }
        }
        return true
    }

    var serverIcon: some View {
        Image(systemName: server.isRemoteOnly ? "globe" : "shippingbox.fill")
            .font(.title)
            .foregroundStyle(server.isRemoteOnly ? .blue : .orange)
            .frame(width: 40, height: 40)
    }
}
