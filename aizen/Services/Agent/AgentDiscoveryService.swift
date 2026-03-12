//
//  AgentDiscoveryService.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import Foundation

/// Service for validating agent executables
extension AgentRegistry {
    nonisolated func validateAgent(named agentName: String) -> Bool {
        guard let metadata = getMetadata(for: agentName) else {
            return false
        }

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
