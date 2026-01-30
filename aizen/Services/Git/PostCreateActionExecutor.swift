//
//  PostCreateActionExecutor.swift
//  aizen
//

import Foundation
import os.log

actor PostCreateActionExecutor {

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen.app", category: "PostCreateActionExecutor")

    struct ExecutionResult {
        let success: Bool
        let output: String
        let error: String?
        let duration: TimeInterval
    }

    /// Execute post-create actions for a repository
    /// - Parameters:
    ///   - actions: Actions to execute
    ///   - newWorktreePath: Path to the newly created worktree
    ///   - mainWorktreePath: Path to the main/primary worktree
    /// - Returns: Execution result
    func execute(
        actions: [PostCreateAction],
        newWorktreePath: String,
        mainWorktreePath: String
    ) async -> ExecutionResult {
        let startTime = Date()

        let enabledActions = actions.filter { $0.enabled }
        guard !enabledActions.isEmpty else {
            return ExecutionResult(success: true, output: "No actions to execute", error: nil, duration: 0)
        }

        let script = PostCreateScriptGenerator.generateScript(from: enabledActions)

        logger.info("Executing post-create script for \(newWorktreePath)")
        logger.debug("Script:\n\(script)")

        // Write script to temp file
        let tempDir = FileManager.default.temporaryDirectory
        let scriptPath = tempDir.appendingPathComponent("aizen-post-create-\(UUID().uuidString).sh")

        do {
            try script.write(to: scriptPath, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath.path)
        } catch {
            logger.error("Failed to write script: \(error.localizedDescription)")
            return ExecutionResult(
                success: false,
                output: "",
                error: "Failed to write script: \(error.localizedDescription)",
                duration: Date().timeIntervalSince(startTime)
            )
        }

        defer {
            try? FileManager.default.removeItem(at: scriptPath)
        }

        // Execute script
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptPath.path, newWorktreePath, mainWorktreePath]
        process.currentDirectoryURL = URL(fileURLWithPath: newWorktreePath)

        // Set up environment
        var environment = ProcessInfo.processInfo.environment
        environment["NEW"] = newWorktreePath
        environment["MAIN"] = mainWorktreePath
        process.environment = environment

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            let outputData = (try? outputPipe.fileHandleForReading.readToEnd()) ?? Data()
            let errorData = (try? errorPipe.fileHandleForReading.readToEnd()) ?? Data()

            let output = String(data: outputData, encoding: .utf8) ?? ""
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

            let duration = Date().timeIntervalSince(startTime)
            let success = process.terminationStatus == 0

            if success {
                logger.info("Post-create script completed successfully in \(String(format: "%.2f", duration))s")
            } else {
                logger.error("Post-create script failed with exit code \(process.terminationStatus): \(errorOutput)")
            }

            return ExecutionResult(
                success: success,
                output: output,
                error: success ? nil : errorOutput,
                duration: duration
            )
        } catch {
            logger.error("Failed to execute script: \(error.localizedDescription)")
            return ExecutionResult(
                success: false,
                output: "",
                error: "Failed to execute: \(error.localizedDescription)",
                duration: Date().timeIntervalSince(startTime)
            )
        }
    }

    /// Execute a single action (for testing/preview)
    func executeAction(
        _ action: PostCreateAction,
        newWorktreePath: String,
        mainWorktreePath: String
    ) async -> ExecutionResult {
        return await execute(
            actions: [action],
            newWorktreePath: newWorktreePath,
            mainWorktreePath: mainWorktreePath
        )
    }
}
