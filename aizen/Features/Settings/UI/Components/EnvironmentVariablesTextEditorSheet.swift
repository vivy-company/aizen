import SwiftUI

struct EnvironmentVariablesTextEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var variables: [AgentEnvironmentVariable]

    @State private var editorContent: String = ""
    @State private var originalText: String = ""
    @State private var currentText: String = ""
    @State private var isLoaded = false

    private var secureCount: Int {
        variables.filter(\.isSecret).count
    }

    private var hasChanges: Bool {
        currentText != originalText
    }

    private var parsedCount: Int {
        parseLines(currentText).count
    }

    var body: some View {
        VStack(spacing: 0) {
            DetailHeaderBar(showsBackground: false) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Edit Environment Variables")
                        .font(.headline)
                    Text("One variable per line in KEY=VALUE format")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } trailing: {
                if hasChanges {
                    TagBadge(
                        text: "\(parsedCount) variable\(parsedCount == 1 ? "" : "s")",
                        color: .orange,
                        font: .caption,
                        backgroundOpacity: 0.2,
                        textColor: .orange
                    )
                }
            }
            .background(AppSurfaceTheme.backgroundColor())

            Divider()

            if isLoaded {
                CodeEditorView(
                    content: editorContent,
                    language: "bash",
                    isEditable: true,
                    onContentChange: { newContent in
                        currentText = newContent
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()

            VStack(spacing: 8) {
                if secureCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                        Text("\(secureCount) Keychain-secured variable\(secureCount == 1 ? " is" : "s are") not shown here. Edit secured values inline in the table.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack {
                    Text("Lines starting with # are comments. Supports KEY=VALUE and export KEY=VALUE.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("Cancel") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)

                    Button("Apply") {
                        applyChanges()
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!hasChanges)
                }
            }
            .padding()
            .background(AppSurfaceTheme.backgroundColor())
        }
        .frame(width: 600, height: 440)
        .settingsSheetChrome()
        .task {
            let text = Self.variablesToText(variables)
            editorContent = text
            originalText = text
            currentText = text
            isLoaded = true
        }
    }

    private func applyChanges() {
        let secureVariables = variables.filter(\.isSecret)
        let secureNames = Set(secureVariables.map(\.trimmedName))
        var parsed = parseLines(currentText)

        for i in parsed.indices {
            if secureNames.contains(parsed[i].trimmedName) {
                parsed[i].isSecret = true
            }
        }

        let parsedNames = Set(parsed.map(\.trimmedName))
        for secureVar in secureVariables where !parsedNames.contains(secureVar.trimmedName) {
            parsed.append(secureVar)
        }

        variables = parsed
        dismiss()
    }

    static func variablesToText(_ vars: [AgentEnvironmentVariable]) -> String {
        let nonSecure = vars.filter { !$0.isSecret }
        if nonSecure.isEmpty {
            return "# Add environment variables here, one per line\n# Example: API_KEY=your-key-here\n"
        }
        return nonSecure.map { variable in
            if variable.trimmedName.isEmpty && variable.value.isEmpty {
                return ""
            }
            return "\(variable.name)=\(variable.value)"
        }
        .joined(separator: "\n") + "\n"
    }

    private func parseLines(_ content: String) -> [AgentEnvironmentVariable] {
        content
            .components(separatedBy: CharacterSet.newlines)
            .compactMap { line -> AgentEnvironmentVariable? in
                let trimmed = line.trimmingCharacters(in: CharacterSet.whitespaces)
                guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), trimmed.contains("=") else {
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
