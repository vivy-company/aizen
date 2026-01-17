//
//  NPMAgentInstaller.swift
//  aizen
//
//  NPM package installation for ACP agents
//

import Foundation
import os.log

actor NPMAgentInstaller {
    static let shared = NPMAgentInstaller()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen.app", category: "NPMInstaller")

    init() {
    }

    // MARK: - Installation

    func install(package: String, targetDir: String) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["npm", "install", "--prefix", targetDir, package]

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
            throw AgentInstallError.installFailed(message: errorMessage)
        }

        if let version = getInstalledVersion(package: package, targetDir: targetDir) {
            saveVersionManifest(version: version, targetDir: targetDir)
            logger.info("Installed \(package) version \(version)")
        }
    }

    // MARK: - Version Detection

    /// Get installed version from local package.json
    func getInstalledVersion(package: String, targetDir: String) -> String? {
        // Strip version specifiers like @latest, @^1.0.0, etc.
        let cleanPackage = stripVersionSpecifier(from: package)

        let packagePath = (targetDir as NSString).appendingPathComponent("node_modules/\(cleanPackage)/package.json")

        guard FileManager.default.fileExists(atPath: packagePath),
              let data = FileManager.default.contents(atPath: packagePath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = json["version"] as? String else {
            return nil
        }

        return version
    }

    /// Strip version specifier from package name (e.g., "opencode-ai@latest" -> "opencode-ai")
    private func stripVersionSpecifier(from package: String) -> String {
        // Handle scoped packages: @scope/name@version -> @scope/name
        if package.hasPrefix("@") {
            // Find the second @ which would be the version specifier
            if let slashIndex = package.firstIndex(of: "/") {
                let afterSlash = package[package.index(after: slashIndex)...]
                if let atIndex = afterSlash.firstIndex(of: "@") {
                    return String(package[..<atIndex])
                }
            }
            return package
        }

        // Simple package: name@version -> name
        if let atIndex = package.firstIndex(of: "@") {
            return String(package[..<atIndex])
        }

        return package
    }

    /// Save version to manifest file for quick lookup
    private func saveVersionManifest(version: String, targetDir: String) {
        let manifestPath = (targetDir as NSString).appendingPathComponent(".version")
        try? version.write(toFile: manifestPath, atomically: true, encoding: .utf8)
    }
}
