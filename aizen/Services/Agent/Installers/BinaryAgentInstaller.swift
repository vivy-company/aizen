//
//  BinaryAgentInstaller.swift
//  aizen
//
//  Binary installation from direct URLs
//

import Foundation

actor BinaryAgentInstaller {
    static let shared = BinaryAgentInstaller()

    private let fileManager: FileManager
    private let urlSession: URLSession

    init(fileManager: FileManager = .default, urlSession: URLSession = .shared) {
        self.fileManager = fileManager
        self.urlSession = urlSession
    }

    // MARK: - Installation

    func install(from urlString: String, agentId: String, targetDir: String) async throws {
        guard let downloadURL = URL(string: urlString) else {
            throw AgentInstallError.downloadFailed(message: "Invalid URL: \(urlString)")
        }

        // Download
        let (tempFileURL, _) = try await urlSession.download(from: downloadURL)

        // Determine archive type
        let isTarball = urlString.hasSuffix(".tar.gz") || urlString.hasSuffix(".tgz")
        let isZip = urlString.hasSuffix(".zip")

        if isTarball {
            try await extractTarball(from: tempFileURL, url: urlString, agentId: agentId, targetDir: targetDir)
        } else if isZip {
            try await extractZip(from: tempFileURL, url: urlString, agentId: agentId, targetDir: targetDir)
        } else {
            try installDirectBinary(from: tempFileURL, agentId: agentId, targetDir: targetDir)
        }
    }

    // MARK: - Tarball Extraction

    private func extractTarball(from tempFileURL: URL, url: String, agentId: String, targetDir: String) async throws {
        let filename = (url as NSString).lastPathComponent
        let tarPath = (targetDir as NSString).appendingPathComponent(filename)
        try fileManager.copyItem(at: tempFileURL, to: URL(fileURLWithPath: tarPath))

        // Untar
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xzf", filename, "-C", targetDir]
        process.currentDirectoryURL = URL(fileURLWithPath: targetDir)

        let errorPipe = Pipe()
        process.standardError = errorPipe

        defer {
            try? errorPipe.fileHandleForReading.close()
        }

        try process.run()
        process.waitUntilExit()

        // Clean up tar file
        try? fileManager.removeItem(atPath: tarPath)

        if process.terminationStatus != 0 {
            let errorData = (try? errorPipe.fileHandleForReading.readToEnd()) ?? Data()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw AgentInstallError.installFailed(message: "Extraction failed: \(errorMessage)")
        }

        // Find and make executable
        let executablePath = findExecutableInDirectory(targetDir, preferredName: agentId)
        if let execPath = executablePath {
            let attributes = [FileAttributeKey.posixPermissions: 0o755]
            try fileManager.setAttributes(attributes, ofItemAtPath: execPath)
            removeQuarantineAttribute(from: execPath)
        }
    }

    // MARK: - Zip Extraction

    private func extractZip(from tempFileURL: URL, url: String, agentId: String, targetDir: String) async throws {
        let filename = (url as NSString).lastPathComponent
        let zipPath = (targetDir as NSString).appendingPathComponent(filename)
        try fileManager.copyItem(at: tempFileURL, to: URL(fileURLWithPath: zipPath))

        // Unzip
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", filename, "-d", targetDir]
        process.currentDirectoryURL = URL(fileURLWithPath: targetDir)

        let errorPipe = Pipe()
        process.standardError = errorPipe

        defer {
            try? errorPipe.fileHandleForReading.close()
        }

        try process.run()
        process.waitUntilExit()

        // Clean up zip file
        try? fileManager.removeItem(atPath: zipPath)

        if process.terminationStatus != 0 {
            let errorData = (try? errorPipe.fileHandleForReading.readToEnd()) ?? Data()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw AgentInstallError.installFailed(message: "Extraction failed: \(errorMessage)")
        }

        // Find and make executable
        let executablePath = findExecutableInDirectory(targetDir, preferredName: agentId)
        if let execPath = executablePath {
            let attributes = [FileAttributeKey.posixPermissions: 0o755]
            try fileManager.setAttributes(attributes, ofItemAtPath: execPath)
            removeQuarantineAttribute(from: execPath)
        }
    }

    // MARK: - Direct Binary

    private func installDirectBinary(from tempFileURL: URL, agentId: String, targetDir: String) throws {
        let executablePath = (targetDir as NSString).appendingPathComponent(agentId)
        try fileManager.copyItem(at: tempFileURL, to: URL(fileURLWithPath: executablePath))

        // Make executable
        let attributes = [FileAttributeKey.posixPermissions: 0o755]
        try fileManager.setAttributes(attributes, ofItemAtPath: executablePath)
        removeQuarantineAttribute(from: executablePath)
    }

    // MARK: - Helpers

    private func findExecutableInDirectory(_ directory: String, preferredName: String) -> String? {
        guard let contents = try? fileManager.contentsOfDirectory(atPath: directory) else {
            return nil
        }

        // Build list of names to check in priority order
        var namesToCheck = [preferredName]

        // Add agent-specific variations
        switch preferredName {
        case "codex":
            namesToCheck.append("codex-acp")
        case "opencode":
            namesToCheck.append("opencode-acp")
        default:
            break
        }

        // Look for preferred names first
        for name in namesToCheck {
            let path = (directory as NSString).appendingPathComponent(name)
            if fileManager.fileExists(atPath: path) {
                return path
            }
        }

        // Look for any executable file
        for item in contents {
            let itemPath = (directory as NSString).appendingPathComponent(item)
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: itemPath, isDirectory: &isDirectory) {
                if !isDirectory.boolValue && fileManager.isExecutableFile(atPath: itemPath) {
                    return itemPath
                }
            }
        }

        return nil
    }

    private func removeQuarantineAttribute(from path: String) {
        // Remove quarantine attribute using xattr to avoid macOS security prompts
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        process.arguments = ["-d", "com.apple.quarantine", path]

        // Suppress output (file might not have quarantine attribute)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try? process.run()
        process.waitUntilExit()
    }
}
