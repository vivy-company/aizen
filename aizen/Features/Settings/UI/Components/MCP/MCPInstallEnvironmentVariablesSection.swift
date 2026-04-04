//
//  MCPInstallEnvironmentVariablesSection.swift
//  aizen
//
//  Created by OpenAI Codex on 05.04.26.
//

import SwiftUI

struct MCPInstallEnvironmentVariablesSection: View {
    let requiredEnvVars: [MCPEnvVar]
    let optionalEnvVars: [MCPEnvVar]
    @Binding var envValues: [String: String]
    @Binding var showSecrets: Set<String>

    var body: some View {
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

    private func binding(for key: String) -> Binding<String> {
        Binding(
            get: { envValues[key] ?? "" },
            set: { envValues[key] = $0 }
        )
    }
}
