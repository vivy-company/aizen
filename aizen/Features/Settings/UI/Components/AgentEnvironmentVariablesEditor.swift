//
//  AgentEnvironmentVariablesEditor.swift
//  aizen
//
//  Native settings-style editor for per-agent environment variable overrides.
//

import SwiftUI
import UniformTypeIdentifiers

struct AgentEnvironmentVariablesEditor: View {
    @Binding var variables: [AgentEnvironmentVariable]

    var helperText: String = "Merged on top of your shell environment each time Aizen launches the agent."

    @State private var revealedSecretIDs: Set<UUID> = []
    @State private var showingFileImporter = false
    @State private var showingTextEditor = false
    @State var importError: String?

    private var duplicateNames: [String] {
        variables.duplicateNames
    }

    private var ignoredValueCount: Int {
        variables.ignoredValueCount
    }

    var body: some View {
        Section {
            if variables.isEmpty {
                emptyState
            } else {
                variablesList
            }

            addButton

            diagnostics
        } header: {
            Text("Environment Variables")
        } footer: {
            Text(helperText)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        HStack(spacing: 8) {
            Image(systemName: "tray")
                .foregroundStyle(.tertiary)
            Text("No environment variables configured")
                .foregroundStyle(.secondary)
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    // MARK: - Variables List

    private let actionButtonsWidth: CGFloat = 54 // lock (24) + spacing (6) + remove (24)

    private var variablesList: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack(spacing: 6) {
                Text("Name")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Value")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.trailing, actionButtonsWidth + 6)

            // Rows
            ForEach(variables.map(\.id), id: \.self) { id in
                variableRow(for: id)
            }
        }
    }

    @ViewBuilder
    private func variableRow(for id: UUID) -> some View {
        if let variable = variable(for: id) {
            let isRevealed = revealedSecretIDs.contains(id)
            let isDuplicate = !variable.trimmedName.isEmpty && duplicateNames.contains(variable.trimmedName)

            HStack(spacing: 6) {
                // Name field
                PlainTextField(text: nameBinding(for: id), isDuplicate: isDuplicate)

                // Value field
                HStack(spacing: 4) {
                    if variable.isSecret && !isRevealed {
                        PlainSecureField(text: valueBinding(for: id))
                    } else {
                        PlainTextField(text: valueBinding(for: id))
                    }

                    if variable.isSecret {
                        Button {
                            toggleReveal(for: id)
                        } label: {
                            Image(systemName: isRevealed ? "eye.slash" : "eye")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .fixedSize()
                        .help(isRevealed ? "Hide value" : "Reveal value")
                    }
                }

                // Fixed-width action buttons
                secureToggle(for: id, variable: variable)

                Button(role: .destructive) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        removeVariable(id: id)
                    }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("Remove variable")
            }
        }
    }

    // MARK: - Field Components

    /// Plain-style TextField with full-width hit area.
    /// Each instance owns its own @FocusState so an invisible overlay can
    /// forward clicks that land outside the tiny underlying NSTextField.
    private struct PlainTextField: View {
        @Binding var text: String
        var isDuplicate: Bool = false
        @FocusState private var isFocused: Bool

        var body: some View {
            TextField(text: $text, prompt: nil) {}
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .focused($isFocused)
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, minHeight: 24)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(isDuplicate ? Color.orange.opacity(0.5) : Color(nsColor: .separatorColor), lineWidth: 0.5)
                )
                .overlay {
                    if !isFocused {
                        Color.white.opacity(0.001)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .onTapGesture { isFocused = true }
                    }
                }
        }
    }

    private struct PlainSecureField: View {
        @Binding var text: String
        @FocusState private var isFocused: Bool

        var body: some View {
            SecureField(text: $text, prompt: nil) {}
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .focused($isFocused)
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, minHeight: 24)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )
                .overlay {
                    if !isFocused {
                        Color.white.opacity(0.001)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .onTapGesture { isFocused = true }
                    }
                }
        }
    }

    private func secureToggle(for id: UUID, variable: AgentEnvironmentVariable) -> some View {
        Button {
            guard let index = variables.firstIndex(where: { $0.id == id }) else { return }
            variables[index].isSecret.toggle()
            if !variables[index].isSecret {
                revealedSecretIDs.remove(id)
            }
        } label: {
            Image(systemName: variable.isSecret ? "lock.fill" : "lock.open")
                .font(.caption)
                .foregroundStyle(variable.isSecret ? Color.blue : Color.secondary.opacity(0.4))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(variable.isSecret ? "Secured — value is stored in macOS Keychain. Click to store as plain text instead." : "Unsecured — value is stored as plain text. Click to protect with macOS Keychain.")
    }

    // MARK: - Actions

    private var addButton: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    variables.append(AgentEnvironmentVariable())
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Color.accentColor)
                    Text("Add Variable")
                }
            }
            .buttonStyle(.plain)

            Menu {
                Button {
                    showingFileImporter = true
                } label: {
                    Label("From File", systemImage: "doc")
                }

                Button {
                    importFromClipboard()
                } label: {
                    Label("From Clipboard", systemImage: "doc.on.clipboard")
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.down")
                        .foregroundStyle(Color.accentColor)
                    Text("Import")
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .menuStyle(.borderlessButton)
            .fixedSize()
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.plainText, .data],
                allowsMultipleSelection: false
            ) { result in
                importEnvFile(result: result)
            }

            Menu {
                ForEach(EnvironmentVariablePreset.categories, id: \.name) { category in
                    Section(category.name) {
                        ForEach(category.presets) { preset in
                            Button(preset.name) {
                                applyPreset(preset)
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "tray.and.arrow.down")
                        .foregroundStyle(Color.accentColor)
                    Text("Presets")
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .menuStyle(.borderlessButton)
            .fixedSize()

            if let error = importError {
                Label(error, systemImage: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer()

            Button {
                showingTextEditor = true
            } label: {
                Image(systemName: "doc.text")
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .help("Edit as text — bulk add/edit variables in KEY=VALUE format")
        }
        .sheet(isPresented: $showingTextEditor) {
            EnvironmentVariablesTextEditorSheet(variables: $variables)
        }
    }

    // MARK: - Diagnostics

    @ViewBuilder
    private var diagnostics: some View {
        if ignoredValueCount > 0 {
            Label {
                Text("Rows without a name are ignored at launch")
                    .font(.caption)
            } icon: {
                Image(systemName: "info.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            .foregroundStyle(.secondary)
        }

        if !duplicateNames.isEmpty {
            Label {
                Text("Duplicate names (\(duplicateNames.joined(separator: ", "))): last value wins")
                    .font(.caption)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private func variable(for id: UUID) -> AgentEnvironmentVariable? {
        variables.first(where: { $0.id == id })
    }

    private func nameBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { variable(for: id)?.name ?? "" },
            set: { newValue in
                guard let index = variables.firstIndex(where: { $0.id == id }) else { return }
                variables[index].name = newValue
            }
        )
    }

    private func valueBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { variable(for: id)?.value ?? "" },
            set: { newValue in
                guard let index = variables.firstIndex(where: { $0.id == id }) else { return }
                variables[index].value = newValue
            }
        )
    }

    private func toggleReveal(for id: UUID) {
        if revealedSecretIDs.contains(id) {
            revealedSecretIDs.remove(id)
        } else {
            revealedSecretIDs.insert(id)
        }
    }

    private func removeVariable(id: UUID) {
        variables.removeAll { $0.id == id }
        revealedSecretIDs.remove(id)
    }

}

// MARK: - Text Editor Sheet

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
            // Header
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

            // Editor
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

            // Footer
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
        // Preserve secure variables that aren't in the text editor
        let secureVariables = variables.filter(\.isSecret)
        let secureNames = Set(secureVariables.map(\.trimmedName))
        var parsed = parseLines(currentText)

        // Re-apply isSecret flag for variables that match existing secure names
        for i in parsed.indices {
            if secureNames.contains(parsed[i].trimmedName) {
                parsed[i].isSecret = true
            }
        }

        // Append secure variables that weren't included in the text
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
            .components(separatedBy: .newlines)
            .compactMap { line -> AgentEnvironmentVariable? in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), trimmed.contains("=") else {
                    return nil
                }

                var effective = trimmed
                if effective.hasPrefix("export ") {
                    effective = String(effective.dropFirst(7)).trimmingCharacters(in: .whitespaces)
                }

                guard let eqIndex = effective.firstIndex(of: "=") else { return nil }

                let name = String(effective[effective.startIndex..<eqIndex])
                    .trimmingCharacters(in: .whitespaces)
                var value = String(effective[effective.index(after: eqIndex)...])
                    .trimmingCharacters(in: .whitespaces)

                guard !name.isEmpty else { return nil }

                if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
                   (value.hasPrefix("'") && value.hasSuffix("'")) {
                    value = String(value.dropFirst().dropLast())
                }

                return AgentEnvironmentVariable(name: name, value: value)
            }
    }
}

// MARK: - Environment Variable Presets

struct EnvironmentVariablePresetEntry {
    let name: String
    let defaultValue: String
    let isSecret: Bool

    init(_ name: String, defaultValue: String = "", isSecret: Bool = true) {
        self.name = name
        self.defaultValue = defaultValue
        self.isSecret = isSecret
    }
}

struct EnvironmentVariablePresetCategory {
    let name: String
    let presets: [EnvironmentVariablePreset]
}

struct EnvironmentVariablePreset: Identifiable {
    let id = UUID()
    let name: String
    let variables: [EnvironmentVariablePresetEntry]

    static let categories: [EnvironmentVariablePresetCategory] = [
        // Claude Code uses Anthropic /v1/messages protocol — only providers with native support
        EnvironmentVariablePresetCategory(name: "Claude Code Provider Override", presets: [
            EnvironmentVariablePreset(name: "via DeepSeek", variables: [
                .init("ANTHROPIC_API_KEY"),
                .init("ANTHROPIC_BASE_URL", defaultValue: "https://api.deepseek.com/anthropic", isSecret: false),
                .init("ANTHROPIC_MODEL", defaultValue: "deepseek-chat", isSecret: false),
            ]),
            EnvironmentVariablePreset(name: "via MiniMax", variables: [
                .init("ANTHROPIC_API_KEY"),
                .init("ANTHROPIC_BASE_URL", defaultValue: "https://api.minimax.io/anthropic", isSecret: false),
                .init("ANTHROPIC_MODEL", isSecret: false),
            ]),
            EnvironmentVariablePreset(name: "via Fireworks AI", variables: [
                .init("ANTHROPIC_API_KEY"),
                .init("ANTHROPIC_BASE_URL", defaultValue: "https://api.fireworks.ai/inference", isSecret: false),
                .init("ANTHROPIC_MODEL", isSecret: false),
            ]),
            EnvironmentVariablePreset(name: "via Alibaba DashScope", variables: [
                .init("ANTHROPIC_API_KEY"),
                .init("ANTHROPIC_BASE_URL", defaultValue: "https://dashscope-intl.aliyuncs.com/apps/anthropic", isSecret: false),
                .init("ANTHROPIC_MODEL", isSecret: false),
            ]),
            EnvironmentVariablePreset(name: "via Requesty", variables: [
                .init("ANTHROPIC_AUTH_TOKEN"),
                .init("ANTHROPIC_BASE_URL", defaultValue: "https://router.requesty.ai", isSecret: false),
                .init("ANTHROPIC_MODEL", isSecret: false),
            ]),
            EnvironmentVariablePreset(name: "via LiteLLM Proxy", variables: [
                .init("ANTHROPIC_AUTH_TOKEN"),
                .init("ANTHROPIC_BASE_URL", defaultValue: "http://localhost:4000", isSecret: false),
                .init("ANTHROPIC_MODEL", isSecret: false),
            ]),
            EnvironmentVariablePreset(name: "via Ollama (Local)", variables: [
                .init("ANTHROPIC_BASE_URL", defaultValue: "http://localhost:11434", isSecret: false),
                .init("ANTHROPIC_AUTH_TOKEN", defaultValue: "ollama", isSecret: false),
                .init("ANTHROPIC_MODEL", isSecret: false),
            ]),
            EnvironmentVariablePreset(name: "via LM Studio (Local)", variables: [
                .init("ANTHROPIC_BASE_URL", defaultValue: "http://localhost:1234", isSecret: false),
                .init("ANTHROPIC_API_KEY", defaultValue: "lmstudio", isSecret: false),
                .init("ANTHROPIC_MODEL", isSecret: false),
            ]),
            EnvironmentVariablePreset(name: "via vLLM (Local)", variables: [
                .init("ANTHROPIC_BASE_URL", defaultValue: "http://localhost:8000", isSecret: false),
                .init("ANTHROPIC_MODEL", isSecret: false),
            ]),
        ]),

        // Codex uses OpenAI /v1/chat/completions — most providers support this
        EnvironmentVariablePresetCategory(name: "Codex Provider Override", presets: [
            EnvironmentVariablePreset(name: "via OpenRouter", variables: [
                .init("OPENAI_API_KEY"),
                .init("OPENAI_BASE_URL", defaultValue: "https://openrouter.ai/api/v1", isSecret: false),
            ]),
            EnvironmentVariablePreset(name: "via DeepSeek", variables: [
                .init("OPENAI_API_KEY"),
                .init("OPENAI_BASE_URL", defaultValue: "https://api.deepseek.com/v1", isSecret: false),
            ]),
            EnvironmentVariablePreset(name: "via Groq", variables: [
                .init("OPENAI_API_KEY"),
                .init("OPENAI_BASE_URL", defaultValue: "https://api.groq.com/openai/v1", isSecret: false),
            ]),
            EnvironmentVariablePreset(name: "via Mistral AI", variables: [
                .init("OPENAI_API_KEY"),
                .init("OPENAI_BASE_URL", defaultValue: "https://api.mistral.ai/v1", isSecret: false),
            ]),
            EnvironmentVariablePreset(name: "via Together AI", variables: [
                .init("OPENAI_API_KEY"),
                .init("OPENAI_BASE_URL", defaultValue: "https://api.together.xyz/v1", isSecret: false),
            ]),
            EnvironmentVariablePreset(name: "via Fireworks AI", variables: [
                .init("OPENAI_API_KEY"),
                .init("OPENAI_BASE_URL", defaultValue: "https://api.fireworks.ai/inference/v1", isSecret: false),
            ]),
            EnvironmentVariablePreset(name: "via xAI (Grok)", variables: [
                .init("OPENAI_API_KEY"),
                .init("OPENAI_BASE_URL", defaultValue: "https://api.x.ai/v1", isSecret: false),
            ]),
            EnvironmentVariablePreset(name: "via MiniMax", variables: [
                .init("OPENAI_API_KEY"),
                .init("OPENAI_BASE_URL", defaultValue: "https://api.minimax.io/v1", isSecret: false),
            ]),
            EnvironmentVariablePreset(name: "via Cerebras", variables: [
                .init("OPENAI_API_KEY"),
                .init("OPENAI_BASE_URL", defaultValue: "https://api.cerebras.ai/v1", isSecret: false),
            ]),
            EnvironmentVariablePreset(name: "via SambaNova", variables: [
                .init("OPENAI_API_KEY"),
                .init("OPENAI_BASE_URL", defaultValue: "https://api.sambanova.ai/v1", isSecret: false),
            ]),
            EnvironmentVariablePreset(name: "via Perplexity", variables: [
                .init("OPENAI_API_KEY"),
                .init("OPENAI_BASE_URL", defaultValue: "https://api.perplexity.ai/v1", isSecret: false),
            ]),
            EnvironmentVariablePreset(name: "via Cohere", variables: [
                .init("OPENAI_API_KEY"),
                .init("OPENAI_BASE_URL", defaultValue: "https://api.cohere.ai/compatibility/v1", isSecret: false),
            ]),
            EnvironmentVariablePreset(name: "via Ollama (Local)", variables: [
                .init("OPENAI_BASE_URL", defaultValue: "http://localhost:11434/v1", isSecret: false),
                .init("OPENAI_API_KEY", defaultValue: "ollama", isSecret: false),
            ]),
        ]),

        // Gemini CLI uses GOOGLE_GEMINI_BASE_URL — only works via proxy for non-Google providers
        EnvironmentVariablePresetCategory(name: "Gemini Provider Override", presets: [
            EnvironmentVariablePreset(name: "via Vertex AI", variables: [
                .init("GOOGLE_APPLICATION_CREDENTIALS", isSecret: false),
                .init("GOOGLE_CLOUD_PROJECT", isSecret: false),
                .init("GOOGLE_CLOUD_LOCATION", defaultValue: "us-central1", isSecret: false),
                .init("GOOGLE_GENAI_USE_VERTEXAI", defaultValue: "true", isSecret: false),
            ]),
            EnvironmentVariablePreset(name: "via LiteLLM Proxy", variables: [
                .init("GEMINI_API_KEY"),
                .init("GOOGLE_GEMINI_BASE_URL", defaultValue: "http://localhost:4000", isSecret: false),
            ]),
        ]),

        EnvironmentVariablePresetCategory(name: "Cloud Platforms", presets: [
            EnvironmentVariablePreset(name: "AWS Bedrock", variables: [
                .init("AWS_ACCESS_KEY_ID"),
                .init("AWS_SECRET_ACCESS_KEY"),
                .init("AWS_REGION", defaultValue: "us-east-1", isSecret: false),
                .init("AWS_SESSION_TOKEN"),
            ]),
            EnvironmentVariablePreset(name: "Azure OpenAI", variables: [
                .init("AZURE_OPENAI_API_KEY"),
                .init("AZURE_API_BASE", isSecret: false),
                .init("AZURE_API_VERSION", defaultValue: "2024-02-01", isSecret: false),
            ]),
            EnvironmentVariablePreset(name: "Google Vertex AI", variables: [
                .init("GOOGLE_APPLICATION_CREDENTIALS", isSecret: false),
                .init("GOOGLE_CLOUD_PROJECT", isSecret: false),
                .init("GOOGLE_CLOUD_LOCATION", defaultValue: "us-central1", isSecret: false),
                .init("GOOGLE_GENAI_USE_VERTEXAI", defaultValue: "true", isSecret: false),
            ]),
        ]),

        EnvironmentVariablePresetCategory(name: "Claude Code", presets: [
            EnvironmentVariablePreset(name: "Custom API Endpoint", variables: [
                .init("ANTHROPIC_API_KEY"),
                .init("ANTHROPIC_BASE_URL", isSecret: false),
                .init("ANTHROPIC_MODEL", isSecret: false),
            ]),
            EnvironmentVariablePreset(name: "Bedrock Routing", variables: [
                .init("CLAUDE_CODE_USE_BEDROCK", defaultValue: "1", isSecret: false),
                .init("AWS_ACCESS_KEY_ID"),
                .init("AWS_SECRET_ACCESS_KEY"),
                .init("AWS_REGION", defaultValue: "us-east-1", isSecret: false),
            ]),
            EnvironmentVariablePreset(name: "Vertex AI Routing", variables: [
                .init("CLAUDE_CODE_USE_VERTEX", defaultValue: "1", isSecret: false),
                .init("ANTHROPIC_VERTEX_PROJECT_ID", isSecret: false),
                .init("CLOUD_ML_REGION", defaultValue: "us-east5", isSecret: false),
            ]),
            EnvironmentVariablePreset(name: "Model Overrides", variables: [
                .init("ANTHROPIC_MODEL", isSecret: false),
                .init("ANTHROPIC_SMALL_FAST_MODEL", isSecret: false),
                .init("CLAUDE_CODE_MAX_OUTPUT_TOKENS", isSecret: false),
                .init("MAX_THINKING_TOKENS", isSecret: false),
            ]),
            EnvironmentVariablePreset(name: "Proxy & TLS", variables: [
                .init("HTTPS_PROXY", isSecret: false),
                .init("NO_PROXY", isSecret: false),
                .init("NODE_EXTRA_CA_CERTS", isSecret: false),
                .init("CLAUDE_CODE_CLIENT_CERT", isSecret: false),
                .init("CLAUDE_CODE_CLIENT_KEY"),
            ]),
        ]),

        EnvironmentVariablePresetCategory(name: "Developer Tools", presets: [
            EnvironmentVariablePreset(name: "GitHub", variables: [
                .init("GITHUB_TOKEN"),
            ]),
            EnvironmentVariablePreset(name: "GitLab", variables: [
                .init("GITLAB_TOKEN"),
            ]),
            EnvironmentVariablePreset(name: "HuggingFace", variables: [
                .init("HF_TOKEN"),
            ]),
            EnvironmentVariablePreset(name: "Voyage AI (Embeddings)", variables: [
                .init("VOYAGE_API_KEY"),
            ]),
            EnvironmentVariablePreset(name: "NPM Registry", variables: [
                .init("NPM_TOKEN"),
            ]),
        ]),

        EnvironmentVariablePresetCategory(name: "Network & Proxy", presets: [
            EnvironmentVariablePreset(name: "HTTP Proxy", variables: [
                .init("HTTP_PROXY", isSecret: false),
                .init("HTTPS_PROXY", isSecret: false),
                .init("NO_PROXY", isSecret: false),
            ]),
            EnvironmentVariablePreset(name: "Custom CA Certificates", variables: [
                .init("NODE_EXTRA_CA_CERTS", isSecret: false),
                .init("NODE_TLS_REJECT_UNAUTHORIZED", defaultValue: "1", isSecret: false),
            ]),
        ]),
    ]
}
