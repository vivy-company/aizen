//
//  AgentValidator.swift
//  aizen
//
//  Synchronous validation helpers for agent executables and commands.
//

import Foundation

nonisolated final class AgentValidator {
    static let shared = AgentValidator()

    private init() {}

    func validate(named agentName: String, snapshot: AgentRegistrySnapshot) -> Bool {
        guard let metadata = snapshot.metadata(for: agentName) else {
            return false
        }

        return validate(metadata: metadata)
    }

    func validate(metadata: AgentMetadata) -> Bool {
        if let command = metadata.command, !command.isEmpty {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["which", command]
            process.environment = ShellEnvironment.loadUserShellEnvironment()
            process.standardOutput = Pipe()
            process.standardError = Pipe()

            do {
                try process.run()
                process.waitUntilExit()
                return process.terminationStatus == 0
            } catch {
                return false
            }
        }

        guard let path = metadata.executablePath else {
            return false
        }

        return FileManager.default.fileExists(atPath: path) &&
            FileManager.default.isExecutableFile(atPath: path)
    }
}
