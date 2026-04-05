import Foundation

extension AgentCatalogStore {
    var allAgents: [AgentMetadata] {
        snapshot.allAgents.map(AgentEnvironmentStore.shared.hydrate)
    }

    var enabledAgents: [AgentMetadata] {
        snapshot.enabledAgents.map(AgentEnvironmentStore.shared.hydrate)
    }

    func metadata(for agentId: String) -> AgentMetadata? {
        snapshot.metadata(for: agentId).map(AgentEnvironmentStore.shared.hydrate)
    }
}
