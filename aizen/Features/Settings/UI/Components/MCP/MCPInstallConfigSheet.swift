//
//  MCPInstallConfigSheet.swift
//  aizen
//
//  Configuration sheet for MCP server installation
//

import SwiftUI

struct MCPInstallConfigSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var mcpManager = MCPManagementStore.shared

    let server: MCPServer
    let agentId: String
    let agentName: String
    let onInstalled: () -> Void

    @State private var selectedPackageIndex = 0
    @State private var selectedRemoteIndex = 0
    @State private var installType: InstallType = .package
    @State private var envValues: [String: String] = [:]
    @State private var showSecrets: Set<String> = []
    @State private var isInstalling = false
    @State private var errorMessage: String?

    private enum InstallType: String, CaseIterable {
        case package = "Package"
        case remote = "Remote"
    }

    private var hasPackages: Bool {
        server.packages != nil && !server.packages!.isEmpty
    }

    private var hasRemotes: Bool {
        server.remotes != nil && !server.remotes!.isEmpty
    }

    private var selectedPackage: MCPPackage? {
        guard hasPackages, selectedPackageIndex < server.packages!.count else { return nil }
        return server.packages![selectedPackageIndex]
    }

    private var selectedRemote: MCPRemote? {
        guard hasRemotes, selectedRemoteIndex < server.remotes!.count else { return nil }
        return server.remotes![selectedRemoteIndex]
    }

    private var requiredEnvVars: [MCPEnvVar] {
        if installType == .package, let package = selectedPackage {
            return package.environmentVariables?.filter { $0.required } ?? []
        }
        return []
    }

    private var optionalEnvVars: [MCPEnvVar] {
        if installType == .package, let package = selectedPackage {
            return package.environmentVariables?.filter { !$0.required } ?? []
        }
        return []
    }

    private var canInstall: Bool {
        for envVar in requiredEnvVars {
            let value = envValues[envVar.name] ?? ""
            if value.trimmingCharacters(in: .whitespaces).isEmpty {
                return false
            }
        }
        return true
    }

    private var serverIcon: some View {
        Image(systemName: server.isRemoteOnly ? "globe" : "shippingbox.fill")
            .font(.title)
            .foregroundStyle(server.isRemoteOnly ? .blue : .orange)
            .frame(width: 40, height: 40)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with icon and basic info
            DetailHeaderBar(showsBackground: false) {
                HStack(alignment: .top, spacing: 12) {
                    // Icon
                    if let icon = server.primaryIcon, let iconUrl = icon.iconUrl, let url = URL(string: iconUrl) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 40, height: 40)
                                    .cornerRadius(8)
                            default:
                                serverIcon
                            }
                        }
                    } else {
                        serverIcon
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(server.displayTitle)
                                .font(.headline)

                            if let version = server.version {
                                TagBadge(text: "v\(version)", color: .secondary)
                            }
                        }

                        Text("Adding to Aizen MCP defaults for \(agentName)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } trailing: {
                // Links
                HStack(spacing: 8) {
                    if let websiteUrl = server.websiteUrl, let url = URL(string: websiteUrl) {
                        Link(destination: url) {
                            Image(systemName: "globe")
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                        .help("Open Website")
                    }

                    if let repoUrl = server.repository?.url, let url = URL(string: repoUrl) {
                        Link(destination: url) {
                            Image(systemName: "link")
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                        .help("Open Project")
                    }
                }
            }
            .background(AppSurfaceTheme.backgroundColor())

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Description
                    if let description = server.description {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("About")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.secondary)

                            Text(description)
                                .font(.callout)
                                .foregroundColor(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.bottom, 4)
                    }

                    Divider()

                    // Source picker (if both are available)
                    if hasPackages && hasRemotes {
                        Picker("Source", selection: $installType) {
                            ForEach(InstallType.allCases, id: \.self) { type in
                                Text(type.rawValue).tag(type)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    // Package selection
                    if installType == .package && hasPackages {
                        MCPInstallSourceDetailsSection.package(
                            server: server,
                            selectedPackageIndex: $selectedPackageIndex,
                            selectedPackage: selectedPackage
                        )
                    }

                    // Remote selection
                    if installType == .remote && hasRemotes {
                        MCPInstallSourceDetailsSection.remote(
                            server: server,
                            selectedRemoteIndex: $selectedRemoteIndex,
                            selectedRemote: selectedRemote
                        )
                    }

                    // Environment variables
                    if installType == .package, !requiredEnvVars.isEmpty || !optionalEnvVars.isEmpty {
                        MCPInstallEnvironmentVariablesSection(
                            requiredEnvVars: requiredEnvVars,
                            optionalEnvVars: optionalEnvVars,
                            envValues: $envValues,
                            showSecrets: $showSecrets
                        )
                    }
                }
                .padding()
            }

            // Error message
            if let error = errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.1))
            }

            Divider()

            // Footer
            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    Task { await install() }
                } label: {
                    if isInstalling {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Add")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!canInstall || isInstalling)
            }
            .padding()
            .background(AppSurfaceTheme.backgroundColor())
        }
        .frame(width: 520, height: 520)
        .settingsSheetChrome()
        .onAppear {
            setupInitialState()
        }
    }

    // MARK: - Helpers

    private func setupInitialState() {
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

    private func install() async {
        isInstalling = true
        errorMessage = nil

        do {
            if installType == .package, let package = selectedPackage {
                try await mcpManager.installPackage(
                    server: server,
                    package: package,
                    agentId: agentId,
                    env: envValues.filter { !$0.value.isEmpty }
                )
            } else if installType == .remote, let remote = selectedRemote {
                try await mcpManager.installRemote(
                    server: server,
                    remote: remote,
                    agentId: agentId,
                    env: [:]
                )
            }
            onInstalled()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }

        isInstalling = false
    }
}
