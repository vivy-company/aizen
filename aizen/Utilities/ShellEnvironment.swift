//
//  ShellEnvironment.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 03.11.25.
//

import Foundation
import os.log

nonisolated enum ShellEnvironment {
    /// Cached environment loaded once at first access
    private static var cachedEnvironment: [String: String]?
    private static let cacheLock = NSLock()
    private static let cacheCondition = NSCondition()
    private static var isLoading = false
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen", category: "ShellEnvironment")

    /// Get user's shell environment (cached after first load)
    /// Warning: On main thread, returns immediately with potentially incomplete environment.
    /// Use `loadUserShellEnvironmentAsync()` for guaranteed complete environment.
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
        
        // Signal any waiters that cache is ready
        cacheCondition.lock()
        cacheCondition.broadcast()
        cacheCondition.unlock()
        
        return env
    }
    
    /// Async version that guarantees the full user shell environment is loaded.
    /// Safe to call from any context (main thread, actors, etc.)
    nonisolated static func loadUserShellEnvironmentAsync() async -> [String: String] {
        // Fast path: already cached
        cacheLock.lock()
        if let cached = cachedEnvironment {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()
        
        // Load on background thread and await result
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let env = loadUserShellEnvironmentBlocking()
                continuation.resume(returning: env)
            }
        }
    }
    
    /// Blocking version that waits for environment to be loaded.
    /// Do NOT call from main thread - use loadUserShellEnvironmentAsync() instead.
    nonisolated static func loadUserShellEnvironmentBlocking() -> [String: String] {
        cacheLock.lock()
        
        if let cached = cachedEnvironment {
            cacheLock.unlock()
            return cached
        }
        
        // Check if another thread is already loading
        if isLoading {
            cacheLock.unlock()
            
            // Wait for the loading thread to finish
            cacheCondition.lock()
            while cachedEnvironment == nil {
                cacheCondition.wait()
            }
            let env = cachedEnvironment!
            cacheCondition.unlock()
            return env
        }
        
        // We'll do the loading
        isLoading = true
        cacheLock.unlock()
        
        let env = loadEnvironmentFromShell()
        
        cacheLock.lock()
        cachedEnvironment = env
        isLoading = false
        cacheLock.unlock()
        
        // Signal any waiters
        cacheCondition.lock()
        cacheCondition.broadcast()
        cacheCondition.unlock()
        
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
        let shell = getLoginShell()
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path

        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)

        let shellName = (shell as NSString).lastPathComponent
        // Use login + interactive shell to source all profile files (.zshrc, .bashrc, etc.)
        // Critical for nvm/fnm/asdf/pyenv which are typically initialized in interactive shell configs
        let arguments: [String]
        switch shellName {
        case "fish":
            arguments = ["-l", "-c", "env"]
        case "zsh", "bash":
            arguments = ["-l", "-i", "-c", "env"]
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

        return shellEnv.isEmpty ? ProcessInfo.processInfo.environment : shellEnv
    }

    nonisolated private static func getLoginShell() -> String {
        if let shell = ProcessInfo.processInfo.environment["SHELL"], !shell.isEmpty {
            return shell
        }

        return "/bin/zsh"
    }
}
