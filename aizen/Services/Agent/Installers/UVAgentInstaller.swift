//
//  UVAgentInstaller.swift
//  aizen
//
//  UV (Python) package installation for ACP agents
//

import Foundation

actor UVAgentInstaller {
    static let shared = UVAgentInstaller()


    init() {
    }

    // MARK: - Installation

    func install(package: String, targetDir: String, executableName: String) async throws {
        // Ensure uv is installed
        try await ensureUVInstalled()

        var shellEnv = await ShellEnvironmentLoader.loadShellEnvironment()

        // Use UV_TOOL_DIR and UV_TOOL_BIN_DIR to install to our managed directory
        // This keeps everything self-contained in ~/.aizen/agents/{agent}/
        shellEnv["UV_TOOL_DIR"] = targetDir
        shellEnv["UV_TOOL_BIN_DIR"] = targetDir

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["uv", "tool", "install", "--force", package]
        process.environment = shellEnv

        let pipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()
        let stdoutData = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
        let stderrData = (try? errorPipe.fileHandleForReading.readToEnd()) ?? Data()
        defer {
            try? pipe.fileHandleForReading.close()
            try? errorPipe.fileHandleForReading.close()
        }

        let stdout = String(data: stdoutData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let combinedOutput = [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n")

        if process.terminationStatus != 0 {
            // Some uv installs return non-zero but still succeed - check if executable exists
            let executablePath = (targetDir as NSString).appendingPathComponent(executableName)
            guard FileManager.default.isExecutableFile(atPath: executablePath) else {
                let errorMessage = combinedOutput.isEmpty ? "Unknown error" : combinedOutput
                throw AgentInstallError.installFailed(message: "uv install failed: \(errorMessage)")
            }
        }

        // Get and save installed version
        if let version = await getInstalledVersion(package: package, shellEnv: shellEnv) {
            saveVersionManifest(version: version, targetDir: targetDir)
        }
        // Version detection failure is non-fatal - package is still installed
    }

    // MARK: - Version Detection

    /// Get installed package version using pip show
    private func getInstalledVersion(package: String, shellEnv: [String: String]) async -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["uv", "pip", "show", package]
        process.environment = shellEnv

        let pipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
            try? pipe.fileHandleForReading.close()
            try? errorPipe.fileHandleForReading.close()
            if let output = String(data: data, encoding: .utf8) {
                // Parse "Version: x.y.z" from pip show output
                for line in output.components(separatedBy: "\n") {
                    if line.hasPrefix("Version:") {
                        let version = line.replacingOccurrences(of: "Version:", with: "").trimmingCharacters(in: .whitespaces)
                        return version
                    }
                }
            }
        } catch {
            try? pipe.fileHandleForReading.close()
            try? errorPipe.fileHandleForReading.close()
        }

        return nil
    }

    /// Save version to manifest file
    private func saveVersionManifest(version: String, targetDir: String) {
        let manifestPath = (targetDir as NSString).appendingPathComponent(".version")
        try? version.write(toFile: manifestPath, atomically: true, encoding: .utf8)
    }

    // MARK: - UV Installation

    private func ensureUVInstalled() async throws {
        let shellEnv = await ShellEnvironmentLoader.loadShellEnvironment()

        // Check if uv is already installed
        let checkProcess = Process()
        checkProcess.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        checkProcess.arguments = ["uv", "--version"]
        checkProcess.environment = shellEnv
        checkProcess.standardOutput = FileHandle.nullDevice
        checkProcess.standardError = FileHandle.nullDevice

        try? checkProcess.run()
        checkProcess.waitUntilExit()

        if checkProcess.terminationStatus == 0 {
            return
        }

        // Install uv using the official installer
        let installProcess = Process()
        installProcess.executableURL = URL(fileURLWithPath: "/bin/sh")
        installProcess.arguments = ["-c", "curl -LsSf https://astral.sh/uv/install.sh | sh"]
        installProcess.environment = shellEnv

        let errorPipe = Pipe()
        installProcess.standardOutput = FileHandle.nullDevice
        installProcess.standardError = errorPipe

        try installProcess.run()
        installProcess.waitUntilExit()
        defer { try? errorPipe.fileHandleForReading.close() }

        if installProcess.terminationStatus != 0 {
            let errorData = (try? errorPipe.fileHandleForReading.readToEnd()) ?? Data()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw AgentInstallError.installFailed(message: "Failed to install uv: \(errorMessage)")
        }
    }
}
