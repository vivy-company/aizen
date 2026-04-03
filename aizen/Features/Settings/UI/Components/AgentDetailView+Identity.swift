import ACP
import SwiftUI
import UniformTypeIdentifiers

extension AgentDetailView {
    @ViewBuilder
    var agentInfoSection: some View {
        Section {
            HStack(spacing: 12) {
                AgentIconView(metadata: metadata, size: 32)
                    .padding(6)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(metadata.name)
                            .font(.title2)
                            .fontWeight(.semibold)

                        if let version = installedVersion {
                            TagBadge(
                                text: version,
                                color: .secondary,
                                font: .caption,
                                backgroundOpacity: 0.1
                            )
                        }

                        if metadata.isCustom {
                            TagBadge(
                                text: "Custom",
                                color: .blue,
                                font: .caption,
                                backgroundOpacity: 0.2
                            )
                        } else {
                            TagBadge(
                                text: "Registry",
                                color: .green,
                                font: .caption,
                                backgroundOpacity: 0.18
                            )
                        }
                    }

                    if let description = metadata.description {
                        Text(description)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { metadata.isEnabled },
                    set: { newValue in
                        let wasEnabled = metadata.isEnabled
                        metadata.isEnabled = newValue
                        Task {
                            await AgentRegistry.shared.updateAgent(metadata)

                            if wasEnabled && !newValue {
                                let defaultAgent = UserDefaults.standard.string(forKey: "defaultACPAgent") ?? AgentRegistry.defaultAgentID
                                if defaultAgent == metadata.id {
                                    if let newDefault = AgentRegistry.shared.getEnabledAgents().first {
                                        await MainActor.run {
                                            UserDefaults.standard.set(newDefault.id, forKey: "defaultACPAgent")
                                        }
                                    }
                                }
                            }
                        }
                    }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }
        }
    }

    @ViewBuilder
    var defaultStatusSection: some View {
        if metadata.isEnabled {
            Section {
                HStack {
                    Label {
                        Text(isDefault ? "This is the default agent" : "Set as default agent")
                    } icon: {
                        Circle()
                            .fill(isDefault ? .blue : .secondary.opacity(0.3))
                            .frame(width: 10, height: 10)
                    }

                    Spacer()

                    if !isDefault {
                        Button("Make Default") {
                            onSetDefault()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    @ViewBuilder
    var executableSection: some View {
        if metadata.isEnabled {
            if metadata.canEditPath {
                Section("Executable") {
                    HStack(spacing: 8) {
                        TextField("Path", text: Binding(
                            get: { metadata.executablePath ?? "" },
                            set: { newValue in
                                metadata.executablePath = newValue.isEmpty ? nil : newValue
                                Task {
                                    await AgentRegistry.shared.updateAgent(metadata)
                                }
                            }
                        ))
                        .textFieldStyle(.roundedBorder)

                        Button("Browse...") {
                            showingFilePicker = true
                        }
                        .buttonStyle(.bordered)

                        if let path = metadata.executablePath, !path.isEmpty {
                            ValidationStatusIcon(
                                isValid: isAgentValid,
                                validHelp: "Executable is valid",
                                invalidHelp: "Executable not found or not executable"
                            )
                        }
                    }

                    if !metadata.launchArgs.isEmpty {
                        Text("Launch arguments: \(metadata.launchArgs.joined(separator: " "))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } else if metadata.isRegistry {
                Section("Launch") {
                    LabeledContent("Type") {
                        Text(metadata.registryDistributionType?.rawValue.uppercased() ?? "Unknown")
                    }

                    if let path = resolvedAgentPath {
                        LabeledContent("Command") {
                            Text(path)
                                .textSelection(.enabled)
                        }
                    }

                    if !resolvedLaunchArgs.isEmpty {
                        LabeledContent("Arguments") {
                            Text(resolvedLaunchArgs.joined(separator: " "))
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    var authenticationSection: some View {
        if metadata.isEnabled {
            Section("Authentication") {
                HStack {
                    Text(authMethodName ?? "Not configured")
                        .foregroundColor(authMethodName != nil ? .primary : .secondary)

                    Spacer()

                    if authMethodName != nil {
                        Button("Change") {
                            AgentRegistry.shared.clearAuthPreference(for: metadata.id)
                            loadAuthStatus()
                            showingAuthClearedMessage = true
                        }
                        .buttonStyle(.bordered)
                    }
                }

                if showingAuthClearedMessage {
                    Text("Auth cleared. New chat sessions will prompt for authentication.")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
        }
    }
}
