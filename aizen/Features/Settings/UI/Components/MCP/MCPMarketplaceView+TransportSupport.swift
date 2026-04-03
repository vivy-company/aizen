import ACP
import Foundation

extension MCPMarketplaceView {
    func loadTransportSupport() async {
        await MainActor.run {
            supportedTransports = ["stdio"]
        }

        guard let path = agentPath,
              FileManager.default.isExecutableFile(atPath: path) else {
            return
        }

        let launchArgs = AgentRegistry.shared.getAgentLaunchArgs(for: agentId)
        let launchEnvironment = await AgentRegistry.shared.resolvedAgentLaunchEnvironment(for: agentId)
        let tempClient = Client()

        do {
            try await tempClient.launch(
                agentPath: path,
                arguments: launchArgs,
                environment: launchEnvironment.isEmpty ? nil : launchEnvironment
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

            var transports: Set<String> = ["stdio"]
            if initResponse.agentCapabilities.mcpCapabilities?.http == true {
                transports.insert("http")
            }
            if initResponse.agentCapabilities.mcpCapabilities?.sse == true {
                transports.insert("sse")
            }

            await MainActor.run {
                supportedTransports = transports
            }
        } catch {
            // Keep stdio-only support on failure
        }
        await tempClient.terminate()
    }

    func isCompatible(server: MCPServer) -> Bool {
        let packageSupported = server.packages?.contains { package in
            supportsTransport(package.transportType)
        } ?? false

        let remoteSupported = server.remotes?.contains { remote in
            supportsTransport(remote.type)
        } ?? false

        return packageSupported || remoteSupported
    }

    func supportsTransport(_ type: String) -> Bool {
        switch type.lowercased() {
        case "stdio":
            return supportedTransports.contains("stdio")
        case "http", "streamable-http":
            return supportedTransports.contains("http")
        case "sse":
            return supportedTransports.contains("sse")
        default:
            return supportedTransports.contains(type.lowercased())
        }
    }
}
