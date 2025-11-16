//
//  AgentUpdater.swift
//  aizen
//
//  Service to update ACP agents
//

import Foundation

enum AgentUpdateError: Error {
    case updateFailed(String)
    case unsupportedInstallMethod
    case agentNotFound
}

actor AgentUpdater {
    static let shared = AgentUpdater()

    private init() {}

    /// Update an agent to the latest version
    func updateAgent(agentName: String, package: String? = nil) async throws {
        let metadata = AgentRegistry.shared.getMetadata(for: agentName)
        guard let installMethod = metadata?.installMethod else {
            throw AgentUpdateError.agentNotFound
        }

        switch installMethod {
        case .npm(let npmPackage):
            try await updateNpmPackage(package: package ?? npmPackage)
        case .githubRelease:
            throw AgentUpdateError.unsupportedInstallMethod
        default:
            throw AgentUpdateError.unsupportedInstallMethod
        }

        // Clear version cache after update
        await AgentVersionChecker.shared.clearCache(for: agentName)
    }

    /// Update an NPM package globally
    private func updateNpmPackage(package: String) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["npm", "install", "-g", "\(package)@latest"]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus != 0 {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                throw AgentUpdateError.updateFailed(errorMessage)
            }
        } catch let error as AgentUpdateError {
            throw error
        } catch {
            throw AgentUpdateError.updateFailed(error.localizedDescription)
        }
    }

    /// Check if update is in progress
    private var updatingAgents: Set<String> = []

    func isUpdating(agentName: String) -> Bool {
        return updatingAgents.contains(agentName)
    }

    /// Update agent with progress tracking
    func updateAgentWithProgress(
        agentName: String,
        onProgress: @escaping @MainActor (String) -> Void
    ) async throws {
        guard !updatingAgents.contains(agentName) else {
            return // Already updating
        }

        updatingAgents.insert(agentName)
        defer { updatingAgents.remove(agentName) }

        let metadata = AgentRegistry.shared.getMetadata(for: agentName)
        guard let installMethod = metadata?.installMethod else {
            throw AgentUpdateError.agentNotFound
        }

        switch installMethod {
        case .npm(let package):
            await MainActor.run { onProgress("Updating \(package)...") }

            do {
                try await updateNpmPackage(package: package)
                await MainActor.run { onProgress("Update complete!") }
                await AgentVersionChecker.shared.clearCache(for: agentName)
            } catch {
                await MainActor.run { onProgress("Update failed: \(error.localizedDescription)") }
                throw error
            }

        default:
            throw AgentUpdateError.unsupportedInstallMethod
        }
    }
}
