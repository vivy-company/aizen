//
//  PostCreateAction.swift
//  aizen
//

import Foundation

// MARK: - Action Types

enum PostCreateActionType: String, Codable, CaseIterable {
    case copyFiles
    case runCommand
    case symlink
    case customScript

    var displayName: String {
        switch self {
        case .copyFiles: return "Copy Files"
        case .runCommand: return "Run Command"
        case .symlink: return "Create Symlink"
        case .customScript: return "Custom Script"
        }
    }

    var icon: String {
        switch self {
        case .copyFiles: return "doc.on.doc"
        case .runCommand: return "bolt.fill"
        case .symlink: return "link"
        case .customScript: return "scroll"
        }
    }

    var actionDescription: String {
        switch self {
        case .copyFiles: return "Copy files from main worktree"
        case .runCommand: return "Run a shell command"
        case .symlink: return "Create symbolic link"
        case .customScript: return "Run custom bash script"
        }
    }
}

// MARK: - Action Model

struct PostCreateAction: Identifiable, Codable, Equatable {
    var id: UUID
    var type: PostCreateActionType
    var enabled: Bool
    var config: ActionConfig

    init(id: UUID = UUID(), type: PostCreateActionType, enabled: Bool = true, config: ActionConfig) {
        self.id = id
        self.type = type
        self.enabled = enabled
        self.config = config
    }

    // Convenience initializers
    static func copyFiles(patterns: [String]) -> PostCreateAction {
        PostCreateAction(type: .copyFiles, config: .copyFiles(CopyFilesConfig(patterns: patterns)))
    }

    static func runCommand(_ command: String, workingDirectory: WorkingDirectory = .newWorktree) -> PostCreateAction {
        PostCreateAction(type: .runCommand, config: .runCommand(RunCommandConfig(command: command, workingDirectory: workingDirectory)))
    }

    static func symlink(source: String, target: String) -> PostCreateAction {
        PostCreateAction(type: .symlink, config: .symlink(SymlinkConfig(source: source, target: target)))
    }

    static func customScript(_ script: String) -> PostCreateAction {
        PostCreateAction(type: .customScript, config: .customScript(CustomScriptConfig(script: script)))
    }
}

// MARK: - Action Configs

enum ActionConfig: Codable, Equatable {
    case copyFiles(CopyFilesConfig)
    case runCommand(RunCommandConfig)
    case symlink(SymlinkConfig)
    case customScript(CustomScriptConfig)
}

struct CopyFilesConfig: Codable, Equatable {
    var patterns: [String]  // e.g., [".env", ".env.local", ".vscode/**"]

    var displayPatterns: String {
        patterns.joined(separator: ", ")
    }
}

enum WorkingDirectory: String, Codable, CaseIterable {
    case newWorktree = "new"
    case mainWorktree = "main"

    var displayName: String {
        switch self {
        case .newWorktree: return "New Worktree"
        case .mainWorktree: return "Main Worktree"
        }
    }
}

struct RunCommandConfig: Codable, Equatable {
    var command: String  // e.g., "bun install"
    var workingDirectory: WorkingDirectory

    init(command: String, workingDirectory: WorkingDirectory = .newWorktree) {
        self.command = command
        self.workingDirectory = workingDirectory
    }
}

struct SymlinkConfig: Codable, Equatable {
    var source: String  // Relative to main worktree, e.g., "node_modules"
    var target: String  // Relative to new worktree, e.g., "node_modules"
}

struct CustomScriptConfig: Codable, Equatable {
    var script: String  // Raw bash script
}

// MARK: - Template Presets

struct PostCreateTemplate: Identifiable, Codable {
    var id: UUID
    var name: String
    var icon: String
    var actions: [PostCreateAction]

    init(id: UUID = UUID(), name: String, icon: String, actions: [PostCreateAction]) {
        self.id = id
        self.name = name
        self.icon = icon
        self.actions = actions
    }

    // Built-in templates
    static let nodeProject = PostCreateTemplate(
        name: "Node.js Project",
        icon: "shippingbox",
        actions: [
            .copyFiles(patterns: [".env", ".env.local", ".env.development"]),
            .runCommand("npm install")
        ]
    )

    static let bunProject = PostCreateTemplate(
        name: "Bun Project",
        icon: "shippingbox",
        actions: [
            .copyFiles(patterns: [".env", ".env.local"]),
            .runCommand("bun install")
        ]
    )

    static let pythonProject = PostCreateTemplate(
        name: "Python Project",
        icon: "chevron.left.forwardslash.chevron.right",
        actions: [
            .copyFiles(patterns: [".env", ".env.local", "config/local.py"]),
            .runCommand("pip install -r requirements.txt")
        ]
    )

    static let swiftProject = PostCreateTemplate(
        name: "Swift/Xcode Project",
        icon: "swift",
        actions: [
            .copyFiles(patterns: [".env", "*.xcconfig"])
        ]
    )

    static let envFilesOnly = PostCreateTemplate(
        name: "Environment Files Only",
        icon: "key",
        actions: [
            .copyFiles(patterns: [".env*", "*.local"])
        ]
    )

    static let builtInTemplates: [PostCreateTemplate] = [
        nodeProject,
        bunProject,
        pythonProject,
        swiftProject,
        envFilesOnly
    ]
}
