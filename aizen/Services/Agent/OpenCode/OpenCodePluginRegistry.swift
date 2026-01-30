//
//  OpenCodePluginRegistry.swift
//  aizen
//
//  Loads the OpenCode plugin registry shipped with the app bundle.
//

import Foundation
import os.log

struct OpenCodePluginDefinition: Codable, Hashable {
    let name: String
    let displayName: String
    let description: String
    let npmPackage: String
    let icon: String?
    let accentColor: String?
    let sortOrder: Int?
}

struct OpenCodePluginRegistry: Codable {
    let version: Int?
    let plugins: [OpenCodePluginDefinition]
}

enum OpenCodePluginRegistryLoader {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen", category: "OpenCodePluginRegistry")

    static func load() -> [OpenCodePluginDefinition] {
        let urls: [URL?] = [
            Bundle.main.url(forResource: "OpenCodePlugins", withExtension: "json"),
            Bundle.main.url(forResource: "OpenCodePlugins", withExtension: "json", subdirectory: "Resources")
        ]

        for url in urls.compactMap({ $0 }) {
            do {
                let data = try Data(contentsOf: url)
                let registry = try JSONDecoder().decode(OpenCodePluginRegistry.self, from: data)
                if !registry.plugins.isEmpty {
                    return registry.plugins
                }
            } catch {
                logger.error("Failed to load OpenCode plugin registry: \(error.localizedDescription)")
            }
        }

        logger.warning("Falling back to built-in OpenCode plugin registry")
        return fallbackPlugins
    }

    private static let fallbackPlugins: [OpenCodePluginDefinition] = [
        OpenCodePluginDefinition(
            name: "oh-my-opencode",
            displayName: "Oh My OpenCode",
            description: "Plugin system with custom agents, hooks, and MCP servers",
            npmPackage: "oh-my-opencode",
            icon: "sparkles",
            accentColor: "purple",
            sortOrder: 0
        ),
        OpenCodePluginDefinition(
            name: "opencode-openai-codex-auth",
            displayName: "OpenAI Codex Auth",
            description: "Authentication for OpenAI Codex models",
            npmPackage: "opencode-openai-codex-auth",
            icon: "key.fill",
            accentColor: "blue",
            sortOrder: 1
        ),
        OpenCodePluginDefinition(
            name: "opencode-gemini-auth",
            displayName: "Gemini Auth",
            description: "Authentication for Google Gemini models",
            npmPackage: "opencode-gemini-auth",
            icon: "bolt.shield.fill",
            accentColor: "orange",
            sortOrder: 2
        ),
        OpenCodePluginDefinition(
            name: "opencode-antigravity-auth",
            displayName: "Antigravity Auth",
            description: "OAuth authentication for Antigravity models",
            npmPackage: "opencode-antigravity-auth",
            icon: "person.crop.circle.badge.checkmark",
            accentColor: "green",
            sortOrder: 3
        )
    ]
}
