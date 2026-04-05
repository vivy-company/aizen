import Foundation

extension AgentRegistry {
    // MARK: - Launch

    func getAgentPath(for agentName: String) -> String? {
        AgentRegistryQueries.agentPath(for: agentName, from: snapshotValue())
    }

    func getAgentLaunchArgs(for agentName: String) -> [String] {
        AgentRegistryQueries.launchArguments(for: agentName, from: snapshotValue())
    }

    func getAgentLaunchEnvironment(for agentName: String) -> [String: String] {
        AgentRegistryQueries.launchEnvironment(for: agentName, from: snapshotValue())
    }

    func resolvedAgentLaunchEnvironment(for agentName: String) async -> [String: String] {
        await launchResolver.resolvedEnvironment(for: agentName, snapshot: snapshotValue())
    }
}
