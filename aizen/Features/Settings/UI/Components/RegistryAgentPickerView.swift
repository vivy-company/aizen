//
//  RegistryAgentPickerView.swift
//  aizen
//

import ACPRegistry
import SwiftUI

struct RegistryAgentPickerView: View {
    @State private var searchText = ""
    @State private var agents: [RegistryAgent] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var addingAgentIDs: Set<String> = []

    private var surfaceColor: Color {
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

    @ViewBuilder
    private var content: some View {
        if isLoading && agents.isEmpty {
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading registry agents...")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(surfaceColor)
        } else if let errorMessage, agents.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 28))
                    .foregroundStyle(.yellow)
                Text("Failed to load the registry")
                    .font(.headline)
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
                Button("Try Again") {
                    Task { await loadAgents(forceRefresh: true) }
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(surfaceColor)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    if let errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.yellow)
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Divider()
                    }

                    if filteredAgents.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 24))
                                .foregroundStyle(.secondary)
                            Text("No Matching Agents")
                                .font(.headline)
                            Text("Try a different search term.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 320)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 16)
                    } else {
                        ForEach(filteredAgents) { agent in
                            RegistryAgentRow(
                                agent: agent,
                                isAdded: AgentRegistry.shared.getMetadata(for: agent.id) != nil,
                                isAdding: addingAgentIDs.contains(agent.id),
                                onAdd: { add(agent) }
                            )

                            Divider()
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(surfaceColor)
        }
    }

    private var filteredAgents: [RegistryAgent] {
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

    private func add(_ agent: RegistryAgent) {
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

    private func loadAgents(forceRefresh: Bool) async {
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
