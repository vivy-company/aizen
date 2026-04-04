//
//  CustomAgentExecutableValidator.swift
//  aizen
//

import ACP
import Foundation

enum CustomAgentExecutableValidator {
    static func validate(
        executablePath: String,
        launchArgs: [String],
        environment: [String: String]
    ) async -> String? {
        do {
            let tempClient = Client()

            try await tempClient.launch(
                agentPath: executablePath,
                arguments: launchArgs,
                environment: environment.isEmpty ? nil : environment
            )

            let capabilities = ClientCapabilities(
                fs: FileSystemCapabilities(
                    readTextFile: true,
                    writeTextFile: true
                ),
                terminal: true,
                meta: [
                    "terminal_output": AnyCodable(true),
                    "terminal-auth": AnyCodable(true)
                ]
            )

            let initResponse = try await tempClient.initialize(
                protocolVersion: 1,
                capabilities: capabilities
            )

            if let authMethods = initResponse.authMethods, !authMethods.isEmpty {
                await tempClient.terminate()
                return nil
            }

            _ = try await tempClient.newSession(
                workingDirectory: FileManager.default.currentDirectoryPath,
                mcpServers: []
            )
            await tempClient.terminate()
            return nil
        } catch {
            return "Not a valid ACP executable: \(error.localizedDescription)"
        }
    }
}
