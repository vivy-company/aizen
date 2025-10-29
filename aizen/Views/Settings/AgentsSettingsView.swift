//
//  AgentsSettingsView.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import SwiftUI

struct AgentsSettingsView: View {
    @Binding var defaultACPAgent: String
    @Binding var claudePath: String
    @Binding var codexPath: String
    @Binding var geminiPath: String
    @Binding var testingAgent: String?
    @Binding var testResult: String?

    var body: some View {
        Form {
            Section(LocalizedStringKey("settings.agents.section")) {
                VStack(alignment: .leading, spacing: 16) {
                    // Claude Agent
                    AgentConfigView(
                        agentName: "claude",
                        agentPath: $claudePath,
                        testingAgent: $testingAgent,
                        testResult: $testResult
                    )

                    Divider()

                    // Codex Agent
                    AgentConfigView(
                        agentName: "codex",
                        agentPath: $codexPath,
                        testingAgent: $testingAgent,
                        testResult: $testResult
                    )

                    Divider()

                    // Gemini Agent
                    AgentConfigView(
                        agentName: "gemini",
                        agentPath: $geminiPath,
                        testingAgent: $testingAgent,
                        testResult: $testResult
                    )

                    Divider()

                    // Default Agent Picker
                    HStack {
                        Text("settings.agents.defaultAgent")
                            .frame(width: 100, alignment: .leading)

                        Picker("", selection: $defaultACPAgent) {
                            Text("settings.agents.claude").tag("claude")
                            Text("settings.agents.codex").tag("codex")
                            Text("settings.agents.gemini").tag("gemini")
                        }
                        .pickerStyle(.segmented)
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct AgentConfigView: View {
    let agentName: String
    @Binding var agentPath: String
    @Binding var testingAgent: String?
    @Binding var testResult: String?

    @State private var isValid: Bool = false
    @State private var isInstalling: Bool = false
    @State private var installError: String?

    var body: some View {
        GroupBox(label: Text(agentName.capitalized).font(.headline)) {
            VStack(spacing: 12) {
                HStack {
                    TextField(LocalizedStringKey("settings.agents.executablePath"), text: $agentPath)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: agentPath) { _, newValue in
                            syncToRegistry()
                            validatePath()
                        }

                    Image(systemName: isValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(isValid ? .green : .red)
                        .opacity(agentPath.isEmpty ? 0 : 1)
                }

                HStack {
                    if !isValid {
                        Button(isInstalling ? LocalizedStringKey("settings.agents.installing") : LocalizedStringKey("settings.agents.install")) {
                            installAgent()
                        }
                        .buttonStyle(.bordered)
                        .disabled(isInstalling)

                        if isInstalling {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                    } else {
                        Button(LocalizedStringKey("settings.agents.testConnection")) {
                            testConnection()
                        }
                        .buttonStyle(.bordered)

                        if testingAgent == agentName {
                            ProgressView()
                                .scaleEffect(0.7)
                        }

                        if let result = testResult, testingAgent == agentName {
                            Text(localizedTestResult(result))
                                .font(.caption)
                                .foregroundColor(result.contains("Success") ? .green : .red)
                        }
                    }

                    if let error = installError {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .lineLimit(2)
                    }

                    Spacer()
                }
            }
            .padding(8)
        }
        .onAppear {
            loadFromRegistry()
            validatePath()
        }
    }

    private func localizedTestResult(_ result: String) -> LocalizedStringKey {
        switch result {
        case "Success":
            return "settings.agents.testResult.success"
        case "Failed":
            return "settings.agents.testResult.failed"
        case "Error":
            return "settings.agents.testResult.error"
        case "Invalid":
            return "settings.agents.testResult.invalid"
        default:
            return LocalizedStringKey(result)
        }
    }

    private func loadFromRegistry() {
        if let path = AgentRegistry.shared.getAgentPath(for: agentName) {
            agentPath = path
        }
    }

    private func syncToRegistry() {
        if !agentPath.isEmpty {
            AgentRegistry.shared.setAgentPath(agentPath, for: agentName)
        }
    }

    private func validatePath() {
        isValid = AgentRegistry.shared.validateAgent(named: agentName)
    }

    private func installAgent() {
        isInstalling = true
        installError = nil

        Task {
            do {
                try await AgentInstaller.shared.installAgent(agentName)
                let execPath = await AgentInstaller.shared.getAgentExecutablePath(agentName)
                await MainActor.run {
                    agentPath = execPath
                    validatePath()
                    isInstalling = false
                }
            } catch {
                await MainActor.run {
                    installError = error.localizedDescription
                    isInstalling = false
                }
            }
        }
    }

    private func testConnection() {
        guard !agentPath.isEmpty else { return }

        testingAgent = agentName
        testResult = nil

        Task {
            // Simple validation: check if file exists and is executable
            let fileManager = FileManager.default
            let exists = fileManager.fileExists(atPath: agentPath)
            let executable = fileManager.isExecutableFile(atPath: agentPath)

            if exists && executable {
                // Try running --version for agents that support it (codex, gemini)
                if agentName != "claude" {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: agentPath)
                    process.arguments = ["--version"]

                    let pipe = Pipe()
                    process.standardOutput = pipe
                    process.standardError = pipe

                    do {
                        try process.run()
                        process.waitUntilExit()

                        await MainActor.run {
                            testResult = process.terminationStatus == 0 ? String(localized: "settings.agents.testResult.success") : String(localized: "settings.agents.testResult.failed")
                        }
                    } catch {
                        await MainActor.run {
                            testResult = String(localized: "settings.agents.testResult.error")
                        }
                    }
                } else {
                    // For claude, just verify file validity
                    await MainActor.run {
                        testResult = String(localized: "settings.agents.testResult.success")
                    }
                }
            } else {
                await MainActor.run {
                    testResult = String(localized: "settings.agents.testResult.invalid")
                }
            }

            await MainActor.run {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    if testingAgent == agentName {
                        testingAgent = nil
                        testResult = nil
                    }
                }
            }
        }
    }
}
