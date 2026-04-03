import Foundation

extension AgentDetailView {
    func loadAuthStatus() {
        authMethodName = AgentRegistry.shared.getAuthMethodName(for: metadata.id)
        showingAuthClearedMessage = false
    }

    func scheduleEnvironmentSave() {
        environmentSaveTask?.cancel()
        var updatedMetadata = metadata
        updatedMetadata.environmentVariables = environmentVariablesDraft
        environmentSaveTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await AgentRegistry.shared.updateAgent(updatedMetadata)
        }
    }

    func loadEnvironmentDraft() {
        environmentVariablesDraft = metadata.environmentVariables
    }

    func flushEnvironmentSaveIfNeeded() {
        environmentSaveTask?.cancel()

        var updatedMetadata = metadata
        updatedMetadata.environmentVariables = environmentVariablesDraft

        Task {
            await AgentRegistry.shared.updateAgent(updatedMetadata)
        }
    }

    func loadRulesPreview() {
        guard let rulesFile = configSpec.rulesFile else {
            rulesPreview = nil
            return
        }

        let path = rulesFile.expandedPath
        guard FileManager.default.fileExists(atPath: path),
              let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            rulesPreview = nil
            return
        }

        let trimmed = content.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        if trimmed.isEmpty {
            rulesPreview = nil
        } else {
            let lines = trimmed.components(separatedBy: CharacterSet.newlines)
            let previewLines = lines.prefix(5).joined(separator: "\n")
            rulesPreview = previewLines
        }
    }

    func loadCommands() {
        guard let commandsDir = configSpec.expandedCommandsDirectory else {
            commands = []
            return
        }

        let fm = FileManager.default
        guard fm.fileExists(atPath: commandsDir),
              let files = try? fm.contentsOfDirectory(atPath: commandsDir) else {
            commands = []
            return
        }

        commands = files
            .filter { $0.hasSuffix(".md") }
            .map { filename in
                let name = String(filename.dropLast(3))
                let path = (commandsDir as NSString).appendingPathComponent(filename)
                return AgentCommand(name: name, path: path)
            }
            .sorted { $0.name < $1.name }
    }
}
