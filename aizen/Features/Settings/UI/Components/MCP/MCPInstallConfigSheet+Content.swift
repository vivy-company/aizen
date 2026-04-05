//
//  MCPInstallConfigSheet+Content.swift
//  aizen
//
//  Content sections for MCP server installation
//

import SwiftUI

extension MCPInstallConfigSheet {
    @ViewBuilder
    var contentView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
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

                if hasPackages && hasRemotes {
                    Picker("Source", selection: $installType) {
                        ForEach(InstallType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if installType == .package && hasPackages {
                    MCPInstallSourceDetailsSection.package(
                        server: server,
                        selectedPackageIndex: $selectedPackageIndex,
                        selectedPackage: selectedPackage
                    )
                }

                if installType == .remote && hasRemotes {
                    MCPInstallSourceDetailsSection.remote(
                        server: server,
                        selectedRemoteIndex: $selectedRemoteIndex,
                        selectedRemote: selectedRemote
                    )
                }

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
    }
}
