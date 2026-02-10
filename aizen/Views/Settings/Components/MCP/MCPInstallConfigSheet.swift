//
//  MCPInstallConfigSheet.swift
//  aizen
//
//  Configuration sheet for MCP server installation
//

import SwiftUI

struct MCPInstallConfigSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var mcpManager = MCPManager.shared

    let server: MCPServer
    let agentId: String
    let agentPath: String?
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

                        Text("Installing to \(agentName)")
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
                        .help("Open Repository")
                    }
                }
            }
            .background(Color(NSColor.controlBackgroundColor))

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

                    // Install type picker (if both available)
                    if hasPackages && hasRemotes {
                        Picker("Install Type", selection: $installType) {
                            ForEach(InstallType.allCases, id: \.self) { type in
                                Text(type.rawValue).tag(type)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    // Package selection
                    if installType == .package && hasPackages {
                        packageSection
                    }

                    // Remote selection
                    if installType == .remote && hasRemotes {
                        remoteSection
                    }

                    // Environment variables
                    if installType == .package, !requiredEnvVars.isEmpty || !optionalEnvVars.isEmpty {
                        envVarsSection
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
                        Text("Install")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!canInstall || isInstalling)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(width: 520, height: 520)
        .onAppear {
            setupInitialState()
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var packageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Package")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.secondary)

                if server.packages!.count > 1 {
                    Picker("Package", selection: $selectedPackageIndex) {
                        ForEach(Array(server.packages!.enumerated()), id: \.offset) { index, pkg in
                            Text("\(pkg.registryBadge): \(pkg.packageName)").tag(index)
                        }
                    }
                    .labelsHidden()
                } else if let package = selectedPackage {
                    HStack(spacing: 8) {
                        TagBadge(text: package.registryBadge, color: .purple)
                        TagBadge(text: package.transportType, color: .gray)
                        Text(package.packageName)
                            .font(.system(.body, design: .monospaced))
                    }
                }
            }

            // Runtime info
            if let package = selectedPackage {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Runtime")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(spacing: 4) {
                        CodePill(
                            text: package.runtimeHint,
                            font: .system(.caption, design: .monospaced),
                            backgroundColor: Color(NSColor.textBackgroundColor),
                            horizontalPadding: 8,
                            verticalPadding: 4
                        )

                        if let runtimeArgs = package.runtimeArguments, !runtimeArgs.isEmpty {
                            CodePill(
                                text: runtimeArgs.map { $0.displayValue }.joined(separator: " "),
                                font: .system(.caption, design: .monospaced),
                                textColor: .secondary,
                                backgroundColor: Color(NSColor.textBackgroundColor),
                                horizontalPadding: 8,
                                verticalPadding: 4
                            )
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var remoteSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Remote")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.secondary)

                if server.remotes!.count > 1 {
                    Picker("Remote", selection: $selectedRemoteIndex) {
                        ForEach(Array(server.remotes!.enumerated()), id: \.offset) { index, remote in
                            Text("\(remote.transportBadge): \(remote.url)").tag(index)
                        }
                    }
                    .labelsHidden()
                } else if let remote = selectedRemote {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            TagBadge(text: remote.transportBadge, color: .blue)
                            TagBadge(text: "Remote", color: .teal)
                        }

                        CodePill(
                            text: remote.url,
                            font: .system(.caption, design: .monospaced),
                            backgroundColor: Color(NSColor.textBackgroundColor),
                            horizontalPadding: 8,
                            verticalPadding: 4,
                            selectable: true,
                            lineLimit: 1
                        )
                    }
                }
            }

            // Headers info (if any)
            if let remote = selectedRemote, let headers = remote.headers, !headers.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Required Headers")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    ForEach(headers, id: \.name) { header in
                        HStack {
                            Text(header.name)
                                .font(.system(.caption, design: .monospaced))
                            if header.isRequired == true {
                                Text("*")
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var envVarsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !requiredEnvVars.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Required Environment Variables")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.secondary)

                    ForEach(requiredEnvVars) { envVar in
                        envVarField(envVar)
                    }
                }
            }

            if !optionalEnvVars.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Optional Environment Variables")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.secondary)

                    ForEach(optionalEnvVars) { envVar in
                        envVarField(envVar)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func envVarField(_ envVar: MCPEnvVar) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(envVar.name)
                    .font(.system(.caption, design: .monospaced))

                if envVar.required {
                    Text("*")
                        .foregroundColor(.red)
                }

                Spacer()
            }

            HStack {
                if envVar.secret && !showSecrets.contains(envVar.name) {
                    SecureField(
                        envVar.default ?? "Enter value...",
                        text: binding(for: envVar.name)
                    )
                    .textFieldStyle(.roundedBorder)
                } else {
                    TextField(
                        envVar.default ?? "Enter value...",
                        text: binding(for: envVar.name)
                    )
                    .textFieldStyle(.roundedBorder)
                }

                if envVar.secret {
                    Button {
                        if showSecrets.contains(envVar.name) {
                            showSecrets.remove(envVar.name)
                        } else {
                            showSecrets.insert(envVar.name)
                        }
                    } label: {
                        Image(systemName: showSecrets.contains(envVar.name) ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.plain)
                }
            }

            if let description = envVar.description {
                Text(description)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Helpers

    private func binding(for key: String) -> Binding<String> {
        Binding(
            get: { envValues[key] ?? "" },
            set: { envValues[key] = $0 }
        )
    }

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
                    agentPath: agentPath,
                    env: envValues.filter { !$0.value.isEmpty }
                )
            } else if installType == .remote, let remote = selectedRemote {
                try await mcpManager.installRemote(
                    server: server,
                    remote: remote,
                    agentId: agentId,
                    agentPath: agentPath,
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
