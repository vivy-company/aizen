//
//  CustomAgentFormView+Executable.swift
//  aizen
//

import AppKit
import Foundation
import SwiftUI

extension CustomAgentFormView {
    @ViewBuilder
    var executableSection: some View {
        Section("ACP Executable") {
            HStack(spacing: 8) {
                TextField("Path", text: executablePathBinding)
                    .textFieldStyle(.roundedBorder)
                    .help("Enter or paste executable path, or use Browse button")
                    .onSubmit {
                        Task {
                            await validateExecutablePath()
                        }
                    }

                Button("Browse...") {
                    selectExecutableFile()
                }
                .buttonStyle(.bordered)
            }

            TextField("Launch arguments (optional)", text: launchArgsTextBinding)
                .textFieldStyle(.roundedBorder)
                .help("Space-separated arguments (e.g., agent stdio, --experimental-acp)")
                .onSubmit {
                    Task {
                        await validateExecutablePath()
                    }
                }

            if !executablePath.isEmpty {
                HStack(spacing: 8) {
                    if isValidatingPath {
                        ProgressView()
                            .scaleEffect(0.7)
                            .controlSize(.small)
                        Text("Validating ACP executable...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let validation = pathValidationResult {
                        switch validation {
                        case .valid:
                            ValidationStatusIcon(isValid: true)
                            Text("Valid ACP executable")
                                .font(.caption)
                                .foregroundStyle(.green)
                        case .invalid(let message):
                            ValidationStatusIcon(isValid: false)
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    } else {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                        Text("Press Enter to validate")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        }
    }

    var executablePathBinding: Binding<String> {
        Binding(
            get: { executablePath },
            set: { updateExecutablePath($0) }
        )
    }

    var launchArgsTextBinding: Binding<String> {
        Binding(
            get: { launchArgsText },
            set: { updateLaunchArgsText($0) }
        )
    }

    var environmentVariablesBinding: Binding<[AgentEnvironmentVariable]> {
        Binding(
            get: { environmentVariables },
            set: { updateEnvironmentVariables($0) }
        )
    }

    var isValid: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedPath = executablePath.trimmingCharacters(in: .whitespaces)

        guard !trimmedName.isEmpty && !trimmedPath.isEmpty else {
            return false
        }

        if case .valid = pathValidationResult {
            return true
        }

        return false
    }

    var parsedLaunchArgs: [String] {
        launchArgsText
            .trimmingCharacters(in: .whitespaces)
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    func selectExecutableFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.message = "Select ACP executable"
        panel.prompt = "Select"

        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window) { response in
                if response == .OK, let url = panel.url {
                    updateExecutablePath(url.path)
                    Task {
                        await validateExecutablePath()
                    }
                }
            }
        } else {
            let response = panel.runModal()
            if response == .OK, let url = panel.url {
                updateExecutablePath(url.path)
                Task {
                    await validateExecutablePath()
                }
            }
        }
    }

    func validateExecutablePath() async {
        let trimmedPath = executablePath.trimmingCharacters(in: .whitespaces)

        guard !trimmedPath.isEmpty else {
            pathValidationResult = .invalid("Path is empty")
            return
        }

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: trimmedPath) else {
            pathValidationResult = .invalid("File does not exist")
            return
        }

        guard fileManager.isExecutableFile(atPath: trimmedPath) else {
            pathValidationResult = .invalid("File is not executable")
            return
        }

        isValidatingPath = true

        let launchArgs = parsedLaunchArgs
        let environment = environmentVariables.launchEnvironment
        let validationMessage = await CustomAgentExecutableValidator.validate(
            executablePath: trimmedPath,
            launchArgs: launchArgs,
            environment: environment
        )
        pathValidationResult = validationMessage.map(PathValidation.invalid) ?? .valid

        await MainActor.run {
            isValidatingPath = false
        }
    }

    func updateExecutablePath(_ newValue: String) {
        executablePath = newValue
        pathValidationResult = nil
    }

    func updateLaunchArgsText(_ newValue: String) {
        launchArgsText = newValue
        pathValidationResult = nil
    }

    func updateEnvironmentVariables(_ newValue: [AgentEnvironmentVariable]) {
        environmentVariables = newValue
        pathValidationResult = nil
    }
}
