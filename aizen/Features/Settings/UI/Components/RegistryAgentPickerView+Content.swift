import ACPRegistry
import SwiftUI

extension RegistryAgentPickerView {
    @ViewBuilder
    var content: some View {
        if isLoading && agents.isEmpty {
            loadingContent
        } else if let errorMessage, agents.isEmpty {
            loadErrorContent(errorMessage)
        } else {
            resultsContent
        }
    }

    var loadingContent: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading registry agents...")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(surfaceColor)
    }

    func loadErrorContent(_ errorMessage: String) -> some View {
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
    }

    var resultsContent: some View {
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
                    emptySearchContent
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

    var emptySearchContent: some View {
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
    }
}
