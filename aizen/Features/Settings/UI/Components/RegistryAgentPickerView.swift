//
//  RegistryAgentPickerView.swift
//  aizen
//

import ACPRegistry
import SwiftUI

struct RegistryAgentPickerView: View {
    @State private var searchText = ""
    @State var agents: [RegistryAgent] = []
    @State var isLoading = false
    @State var errorMessage: String?
    @State var addingAgentIDs: Set<String> = []

    var surfaceColor: Color {
        AppSurfaceTheme.backgroundColor()
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            content
        }
        .frame(minWidth: 700, idealWidth: 860, maxWidth: .infinity, minHeight: 520, idealHeight: 720, maxHeight: .infinity)
        .background(surfaceColor)
        .toolbarBackground(surfaceColor, for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    Task { await loadAgents(forceRefresh: true) }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(isLoading)
            }
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search registry agents")
        .task {
            guard agents.isEmpty else { return }
            await loadAgents(forceRefresh: false)
        }
    }

    private var headerView: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Add From Registry")
                    .font(.headline)
                Text("Discover ACP-compatible agents from the official registry.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !agents.isEmpty {
                TagBadge(text: "\(filteredAgents.count) shown", color: .secondary, cornerRadius: 6)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(surfaceColor)
    }

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
