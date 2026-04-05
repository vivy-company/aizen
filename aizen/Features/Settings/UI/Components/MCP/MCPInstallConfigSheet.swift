//
//  MCPInstallConfigSheet.swift
//  aizen
//
//  Configuration sheet for MCP server installation
//

import SwiftUI

struct MCPInstallConfigSheet: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var mcpManager = MCPManagementStore.shared

    let server: MCPServer
    let agentId: String
    let agentName: String
    let onInstalled: () -> Void

    @State var selectedPackageIndex = 0
    @State var selectedRemoteIndex = 0
    @State var installType: InstallType = .package
    @State var envValues: [String: String] = [:]
    @State var showSecrets: Set<String> = []
    @State var isInstalling = false
    @State var errorMessage: String?

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

    var body: some View {
        VStack(spacing: 0) {
            headerView

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
            MCPInstallConfigSupport.setupInitialState(
                hasPackages: hasPackages,
                hasRemotes: hasRemotes,
                selectedPackage: selectedPackage,
                installType: &installType,
                envValues: &envValues
            )
        }
    }

}
