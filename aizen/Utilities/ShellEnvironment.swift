//
//  ShellEnvironment.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 03.11.25.
//

import Foundation
import os.log

enum ShellEnvironment {
    /// Cached environment loaded once at first access
    private static var cachedEnvironment: [String: String]?
    private static let cacheLock = NSLock()
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen", category: "ShellEnvironment")

    /// Get user's shell environment (cached after first load)
    nonisolated static func loadUserShellEnvironment() -> [String: String] {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        if let cached = cachedEnvironment {
            return cached
        }

        // Never block the UI thread on a login-shell spawn.
        // Return a best-effort environment immediately and warm the cache asynchronously.
        if Thread.isMainThread {
            DispatchQueue.global(qos: .utility).async {
                _ = loadUserShellEnvironment()
            }
            return ProcessInfo.processInfo.environment
        }

        let env = loadEnvironmentFromShell()
        cachedEnvironment = env
        return env
    }

    /// Preload environment in background (call at app launch)
    nonisolated static func preloadEnvironment() {
        DispatchQueue.global(qos: .userInitiated).async {
            _ = loadUserShellEnvironment()
        }
    }

    /// Force reload of environment (e.g., after user changes shell config)
    nonisolated static func reloadEnvironment() {
        cacheLock.lock()
        cachedEnvironment = nil
        cacheLock.unlock()
        preloadEnvironment()
    }

    private nonisolated static func loadEnvironmentFromShell() -> [String: String] {
        let startTime = CFAbsoluteTimeGetCurrent()
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
            logger.error("Failed to load shell environment: \(error.localizedDescription)")
            return ProcessInfo.processInfo.environment
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        logger.debug("Shell environment loaded in \(String(format: "%.2f", elapsed * 1000))ms")

        return shellEnv.isEmpty ? ProcessInfo.processInfo.environment : shellEnv
    }

    nonisolated private static func getLoginShell() -> String {
        if let shell = ProcessInfo.processInfo.environment["SHELL"], !shell.isEmpty {
            return shell
        }

        return "/bin/zsh"
    }
}
