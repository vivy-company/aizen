//
//  AgentCatalogStore.swift
//  aizen
//
//  Main-actor agent catalog snapshot for SwiftUI consumers.
//

import Combine
import Foundation

@MainActor
final class AgentCatalogStore: ObservableObject {
    static let shared = AgentCatalogStore()

    @Published private(set) var snapshot: AgentRegistrySnapshot = .empty

    private init() {}

    func update(snapshot: AgentRegistrySnapshot) {
        self.snapshot = snapshot
    }

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
