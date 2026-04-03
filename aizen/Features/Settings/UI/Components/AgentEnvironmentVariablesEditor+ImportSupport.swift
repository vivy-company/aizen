import SwiftUI

extension AgentEnvironmentVariablesEditor {
    func applyPreset(_ preset: EnvironmentVariablePreset) {
        let existingNames = Set(variables.map(\.trimmedName))
        let newVars = preset.variables
            .filter { !existingNames.contains($0.name) }
            .map { AgentEnvironmentVariable(name: $0.name, value: $0.defaultValue, isSecret: $0.isSecret) }

        guard !newVars.isEmpty else {
            importError = "All variables from this preset already exist"
            return
        }

        importError = nil
        withAnimation(.easeInOut(duration: 0.2)) {
            variables.append(contentsOf: newVars)
        }
    }

    func importFromClipboard() {
        importError = nil

        guard let content = NSPasteboard.general.string(forType: .string), !content.isEmpty else {
            importError = "Clipboard is empty"
            return
        }

        let parsed = parseEnvFile(content)
        if parsed.isEmpty {
            importError = "No variables found in clipboard"
            return
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            variables.append(contentsOf: parsed)
        }
    }

    func importEnvFile(result: Result<[URL], Error>) {
        importError = nil

        switch result {
        case .failure(let error):
            importError = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }

            guard url.startAccessingSecurityScopedResource() else {
                importError = "Cannot access file"
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            guard let content = try? String(contentsOf: url, encoding: .utf8) else {
                importError = "Could not read file"
                return
            }

            let parsed = parseEnvFile(content)
            if parsed.isEmpty {
                importError = "No variables found"
                return
            }

            withAnimation(.easeInOut(duration: 0.2)) {
                variables.append(contentsOf: parsed)
            }
        }
    }

    func parseEnvFile(_ content: String) -> [AgentEnvironmentVariable] {
        content
            .components(separatedBy: CharacterSet.newlines)
            .compactMap { line -> AgentEnvironmentVariable? in
                let trimmed = line.trimmingCharacters(in: CharacterSet.whitespaces)

                guard !trimmed.isEmpty,
                      !trimmed.hasPrefix("#"),
                      trimmed.contains("=") else {
                    return nil
                }

                var effective = trimmed
                if effective.hasPrefix("export ") {
                    effective = String(effective.dropFirst(7)).trimmingCharacters(in: CharacterSet.whitespaces)
                }

                guard let eqIndex = effective.firstIndex(of: "=") else { return nil }

                let name = String(effective[effective.startIndex..<eqIndex])
                    .trimmingCharacters(in: CharacterSet.whitespaces)
                var value = String(effective[effective.index(after: eqIndex)...])
                    .trimmingCharacters(in: CharacterSet.whitespaces)

                guard !name.isEmpty else { return nil }

                if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
                   (value.hasPrefix("'") && value.hasSuffix("'")) {
                    value = String(value.dropFirst().dropLast())
                }

                return AgentEnvironmentVariable(name: name, value: value)
            }
    }
}
