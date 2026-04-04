import ACPRegistry
import Foundation

extension RegistryAgentPickerView {
    var filteredAgents: [RegistryAgent] {
        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let visibleAgents = agents.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        guard !trimmedQuery.isEmpty else {
            return visibleAgents
        }

        return visibleAgents.filter { agent in
            agent.name.localizedCaseInsensitiveContains(trimmedQuery) ||
            agent.id.localizedCaseInsensitiveContains(trimmedQuery) ||
            agent.description.localizedCaseInsensitiveContains(trimmedQuery) ||
            (agent.repository?.localizedCaseInsensitiveContains(trimmedQuery) ?? false)
        }
    }

    func add(_ agent: RegistryAgent) {
        guard !addingAgentIDs.contains(agent.id) else { return }

        addingAgentIDs.insert(agent.id)

        Task {
            do {
                _ = try await ACPRegistryService.shared.addAgent(agent)
                await MainActor.run {
                    _ = addingAgentIDs.remove(agent.id)
                }
            } catch {
                await MainActor.run {
                    _ = addingAgentIDs.remove(agent.id)
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    func loadAgents(forceRefresh: Bool) async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }

        do {
            let fetchedAgents = try await ACPRegistryService.shared.fetchAgents(forceRefresh: forceRefresh)
            await MainActor.run {
                agents = fetchedAgents
                isLoading = false
            }
        } catch {
            await MainActor.run {
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }
}
