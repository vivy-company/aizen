import Foundation

extension AgentRegistry {
    // MARK: - Internal

    nonisolated func bootstrapDefaultAgents() async {
        await mutationGate.perform {
            let currentSnapshot = snapshotValue()
            let mergedSnapshot = await store.bootstrapSnapshot(from: currentSnapshot)
            applySnapshot(mergedSnapshot)
            ensureDefaultAgentPreference(for: mergedSnapshot)
        }
    }

    nonisolated func snapshotValue() -> AgentRegistrySnapshot {
        stateLock.lock()
        defer { stateLock.unlock() }
        return cachedSnapshot
    }

    nonisolated func applySnapshot(_ snapshot: AgentRegistrySnapshot, notify: Bool = true) {
        stateLock.lock()
        cachedSnapshot = snapshot
        stateLock.unlock()

        Task { @MainActor in
            AgentCatalogStore.shared.update(snapshot: snapshot)
        }

        if notify {
            NotificationCenter.default.post(name: .agentMetadataDidChange, object: nil)
        }
    }

    nonisolated func ensureDefaultAgentPreference(for snapshot: AgentRegistrySnapshot) {
        let defaultAgent = defaults.string(forKey: "defaultACPAgent")
        if defaultAgent == nil || snapshot.metadata(for: defaultAgent ?? "") == nil {
            defaults.set(Self.defaultAgentID, forKey: "defaultACPAgent")
        }
    }
}
