//
//  ShellEnvironment.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 03.11.25.
//

import Foundation

enum ShellEnvironment {
    nonisolated static func loadUserShellEnvironment() -> [String: String] {
        let shell = getLoginShell()
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path

        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)

        let shellName = (shell as NSString).lastPathComponent
        let arguments: [String]
        switch shellName {
        case "fish":
            arguments = ["-l", "-c", "env"]
        case "zsh", "bash":
            arguments = ["-l", "-c", "env"]
        case "sh":
            arguments = ["-l", "-c", "env"]
        default:
            arguments = ["-c", "env"]
        }

        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: homeDir)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        var shellEnv: [String: String] = [:]

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                for line in output.split(separator: "\n") {
                    if let equalsIndex = line.firstIndex(of: "=") {
                        let key = String(line[..<equalsIndex])
                        let value = String(line[line.index(after: equalsIndex)...])
                        shellEnv[key] = value
                    }
                }
            }
        } catch {
            return ProcessInfo.processInfo.environment
        }

        return shellEnv.isEmpty ? ProcessInfo.processInfo.environment : shellEnv
    }

    nonisolated private static func getLoginShell() -> String {
        if let shell = ProcessInfo.processInfo.environment["SHELL"], !shell.isEmpty {
            return shell
        }

        return "/bin/zsh"
    }
}
