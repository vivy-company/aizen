//
//  ScriptAgentInstaller.swift
//  aizen
//
//  Script-based installation for ACP agents
//

import Foundation
import os.log

actor ScriptAgentInstaller {
    static let shared = ScriptAgentInstaller()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen.app", category: "ScriptInstaller")

    // MARK: - Installation

    func install(from urlString: String) async throws {
        guard URL(string: urlString) != nil else {
            throw AgentInstallError.downloadFailed(message: "Invalid URL: \(urlString)")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")

        let escapedURL = shellEscape(urlString)
        let command = "/usr/bin/curl -fsSL \(escapedURL) | /bin/sh"
        process.arguments = ["-c", command]

        let shellEnv = await ShellEnvironmentLoader.loadShellEnvironment()
        process.environment = shellEnv

        let pipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()
        defer {
            try? pipe.fileHandleForReading.close()
            try? errorPipe.fileHandleForReading.close()
        }

        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            logger.error("Script install failed: \(errorMessage)")
            throw AgentInstallError.installFailed(message: errorMessage)
        }
    }

    // MARK: - Helpers

    private func shellEscape(_ value: String) -> String {
        // Safe single-quote escaping for shell commands.
        return "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}
