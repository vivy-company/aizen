//
//  AgentSetupDialog.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 03.11.25.
//

import SwiftUI

struct AgentSetupDialog: View {
    @ObservedObject var session: AgentSession
    @Environment(\.dismiss) private var dismiss

    @State private var isAutoDiscovering = false
    @State private var isInstalling = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)

                Text("agentSetup.title", bundle: .main)
                    .font(.title2)
                    .fontWeight(.semibold)

                if let agentName = session.missingAgentName {
                    Text("agentSetup.message.\(agentName)", bundle: .main)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.top, 20)

            Divider()

            // Options
            VStack(spacing: 12) {
                // Auto Discover
                Button {
                    autoDiscover()
                } label: {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 16))
                                .foregroundStyle(.blue)

                            Text("agentSetup.autoDiscover.title", bundle: .main)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.primary)

                            Spacer()

                            if isAutoDiscovering {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Text("agentSetup.autoDiscover.description", bundle: .main)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(.separator.opacity(0.3), lineWidth: 0.5)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isAutoDiscovering || isInstalling)

                // Install
                Button {
                    installAgent()
                } label: {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.down.circle")
                                .font(.system(size: 16))
                                .foregroundStyle(.blue)

                            Text("agentSetup.install.title", bundle: .main)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.primary)

                            Spacer()

                            if isInstalling {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Text("agentSetup.install.description", bundle: .main)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(.separator.opacity(0.3), lineWidth: 0.5)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isAutoDiscovering || isInstalling)

                // Manual Path
                Button {
                    selectManualPath()
                } label: {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "folder")
                                .font(.system(size: 16))
                                .foregroundStyle(.blue)

                            Text("agentSetup.manualPath.title", bundle: .main)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.primary)

                            Spacer()

                            Image(systemName: "arrow.right")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }

                        Text("agentSetup.manualPath.description", bundle: .main)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(.separator.opacity(0.3), lineWidth: 0.5)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isAutoDiscovering || isInstalling)
            }
            .padding(.horizontal)

            // Error message
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
                    .multilineTextAlignment(.center)
            }

            Divider()

            // Footer
            HStack {
                Button {
                    dismiss()
                } label: {
                    Text("chat.button.cancel", bundle: .main)
                }
                .keyboardShortcut(.escape)

                Spacer()

                Button {
                    openSettings()
                } label: {
                    Text("agentSetup.openSettings", bundle: .main)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
        .frame(width: 500)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func autoDiscover() {
        guard let agentName = session.missingAgentName else { return }

        isAutoDiscovering = true
        errorMessage = nil

        Task {
            // Discover only the missing agent
            let discoveredPath = await AgentRegistry.shared.discoverAgent(named: agentName)

            await MainActor.run {
                isAutoDiscovering = false
            }

            if let path = discoveredPath {
                // Set the discovered path
                await AgentRegistry.shared.setAgentPath(path, for: agentName)
                await MainActor.run {
                    retrySession()
                }
            } else {
                await MainActor.run {
                    errorMessage = String(localized: "agentSetup.error.notFound.\(agentName)")
                }
            }
        }
    }

    private func installAgent() {
        guard let agentName = session.missingAgentName else { return }

        isInstalling = true
        errorMessage = nil

        Task {
            do {
                try await AgentInstaller.shared.installAgent(agentName)

                await MainActor.run {
                    isInstalling = false
                    retrySession()
                }
            } catch {
                await MainActor.run {
                    isInstalling = false
                    errorMessage = String(format: String(localized: "agentSetup.error.installFailed"), error.localizedDescription)
                }
            }
        }
    }

    private func selectManualPath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.message = String(localized: "agentSetup.selectExecutable")

        panel.begin { response in
            if response == .OK, let url = panel.url {
                let path = url.path

                // Validate and save
                if let agentName = session.missingAgentName {
                    Task {
                        await AgentRegistry.shared.setAgentPath(path, for: agentName)

                        let isValid = await AgentRegistry.shared.validateAgent(named: agentName)
                        await MainActor.run {
                            if isValid {
                                retrySession()
                            } else {
                                errorMessage = String(localized: "agentSetup.error.invalidExecutable")
                            }
                        }
                    }
                }
            }
        }
    }

    private func retrySession() {
        Task {
            do {
                try await session.retryStart()
                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = String(format: String(localized: "agentSetup.error.sessionFailed"), error.localizedDescription)
                }
            }
        }
    }

    private func openSettings() {
        dismiss()
        // Post notification to open settings
        NotificationCenter.default.post(name: NSNotification.Name("OpenSettings"), object: nil)
    }
}
