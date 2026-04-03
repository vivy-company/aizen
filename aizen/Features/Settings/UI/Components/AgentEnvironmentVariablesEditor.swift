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

    @State var revealedSecretIDs: Set<UUID> = []
    @State private var showingFileImporter = false
    @State private var showingTextEditor = false
    @State var importError: String?

    var duplicateNames: [String] {
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

    let actionButtonsWidth: CGFloat = 54 // lock (24) + spacing (6) + remove (24)

    // MARK: - Field Components

    /// Plain-style TextField with full-width hit area.
    /// Each instance owns its own @FocusState so an invisible overlay can
    /// forward clicks that land outside the tiny underlying NSTextField.
    struct PlainTextField: View {
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

    struct PlainSecureField: View {
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
