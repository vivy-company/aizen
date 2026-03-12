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

    @State private var isInstalling = false
    @State private var errorMessage: String?

    private var canInstallAgent: Bool {
        guard let agentName = session.missingAgentName,
              let metadata = AgentRegistry.shared.getMetadata(for: agentName) else {
            return false
        }
        return metadata.requiresInstall
    }

    private var agentDisplayName: String {
        guard let agentName = session.missingAgentName else { return "Agent" }
        return AgentRegistry.shared.getMetadata(for: agentName)?.name ?? agentName.capitalized
    }

    var body: some View {
        VStack(spacing: 16) {
            if isInstalling {
                // Simple loading state
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.2)

                    Text("Installing \(agentDisplayName)...")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(40)
            } else if let error = errorMessage {
                // Error state
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.red)

                    Text("Installation Failed")
                        .font(.headline)

                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    HStack(spacing: 12) {
                        Button("Cancel") {
                            dismiss()
                        }
                        .keyboardShortcut(.escape)

                        Button("Retry") {
                            installAgent()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.top, 8)
                }
                .padding(24)
            } else {
                VStack(spacing: 12) {
                    if canInstallAgent {
                        ProgressView()
                        Text("Preparing...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                        Text("Install this agent from the registry or verify its command dependencies.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(40)
            }
        }
        .frame(width: 300, height: 200)
        .background(AppSurfaceTheme.backgroundColor())
        .task {
            if canInstallAgent && !isInstalling && errorMessage == nil {
                installAgent()
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
                try await session.retryStart()
                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isInstalling = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
