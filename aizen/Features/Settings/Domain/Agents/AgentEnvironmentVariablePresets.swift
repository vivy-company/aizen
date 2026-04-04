//
//  AgentEnvironmentVariablePresets.swift
//  aizen
//
//  Created by OpenAI Codex on 04.04.26.
//

import Foundation

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
