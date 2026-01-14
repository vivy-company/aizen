//
//  ShellEnvironmentLoader.swift
//  aizen
//
//  Shell environment loading for process execution
//

import Foundation

enum ShellEnvironmentLoader {
    
    // MARK: - Environment Loading
    
    static func loadShellEnvironment() async -> [String: String] {
        await Task.detached {
            let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
            let shellName = (shell as NSString).lastPathComponent

            let process = Process()
            process.executableURL = URL(fileURLWithPath: shell)

            let arguments: [String]
            switch shellName {
            case "fish":
                arguments = ["-l", "-c", "env"]
            case "zsh", "bash", "sh":
                arguments = ["-l", "-i", "-c", "env"]
            default:
                arguments = ["-c", "env"]
            }

            process.arguments = arguments

            let pipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = pipe
            process.standardError = errorPipe

            var shellEnv: [String: String] = [:]

            do {
                try process.run()
                process.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                try? pipe.fileHandleForReading.close()
                try? errorPipe.fileHandleForReading.close()
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
                try? pipe.fileHandleForReading.close()
                try? errorPipe.fileHandleForReading.close()
                return ProcessInfo.processInfo.environment
            }

            return shellEnv.isEmpty ? ProcessInfo.processInfo.environment : shellEnv
        }.value
    }
}
