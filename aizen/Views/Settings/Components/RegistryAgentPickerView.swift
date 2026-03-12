//
//  RegistryAgentPickerView.swift
//  aizen
//

import ACPRegistry
import SwiftUI

struct RegistryAgentPickerView: View {
    @Environment(\.dismiss) private var dismiss

    let onAgentAdded: (() -> Void)?

    @State private var searchText = ""
    @State private var agents: [RegistryAgent] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var addingAgentIDs: Set<String> = []

    init(onAgentAdded: (() -> Void)? = nil) {
        self.onAgentAdded = onAgentAdded
    }

    var body: some View {
        VStack(spacing: 0) {
            DetailHeaderBar(showsBackground: false) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add From Registry")
                        .font(.headline)
                    Text("Discover ACP-compatible agents from the official registry.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } trailing: {
                HStack(spacing: 8) {
                    Button {
                        Task { await loadAgents(forceRefresh: true) }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(isLoading)

                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .background(AppSurfaceTheme.backgroundColor())

            Divider()

            searchBar

            Divider()

            content

            if let errorMessage, !agents.isEmpty {
                Divider()

                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(AppSurfaceTheme.backgroundColor())
            }
        }
        .frame(width: 620, height: 760)
        .settingsSheetChrome()
        .task {
            guard agents.isEmpty else { return }
            await loadAgents(forceRefresh: false)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            SearchField(
                placeholder: "Search registry agents",
                text: $searchText,
                iconColor: .secondary,
                onClear: {}
            ) {
                EmptyView()
            }
            .padding(10)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(10)

            Text("\(filteredAgents.count) shown")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(AppSurfaceTheme.backgroundColor())
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
            .background(AppSurfaceTheme.backgroundColor())
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
            .background(AppSurfaceTheme.backgroundColor())
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
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
                    } else {
                        ForEach(filteredAgents) { agent in
                            RegistryAgentRow(
                                agent: agent,
                                isAdded: AgentRegistry.shared.getMetadata(for: agent.id) != nil,
                                isAdding: addingAgentIDs.contains(agent.id),
                                onAdd: { add(agent) }
                            )
                        }
                    }
                }
                .padding(16)
            }
            .background(AppSurfaceTheme.backgroundColor())
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
                    addingAgentIDs.remove(agent.id)
                    onAgentAdded?()
                }
            } catch {
                await MainActor.run {
                    addingAgentIDs.remove(agent.id)
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

private struct RegistryAgentRow: View {
    let agent: RegistryAgent
    let isAdded: Bool
    let isAdding: Bool
    let onAdd: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            RegistryRemoteIconView(iconURL: agent.icon, size: 28) {
                Image(systemName: "brain.head.profile")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.secondary)
                    .padding(4)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(agent.name)
                        .font(.headline)
                    Text(agent.version)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(agent.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)

                HStack(spacing: 6) {
                    ForEach(distributionBadges, id: \.self) { badge in
                        TagBadge(
                            text: badge,
                            color: .secondary,
                            font: .caption2,
                            horizontalPadding: 8,
                            verticalPadding: 4,
                            backgroundOpacity: 0.14,
                            textColor: .secondary
                        )
                    }

                    if let repository = agent.repository,
                       let repositoryURL = URL(string: repository) {
                        Link("Repository", destination: repositoryURL)
                            .font(.caption2)
                    }
                }
            }

            Spacer(minLength: 12)

            actionView
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var actionView: some View {
        if isAdded {
            Text("Added")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        } else if isAdding {
            ProgressView()
                .controlSize(.small)
                .padding(.top, 4)
        } else {
            Button("Add") {
                onAdd()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var distributionBadges: [String] {
        var badges: [String] = []
        if agent.distribution.binary != nil {
            badges.append("Binary")
        }
        if agent.distribution.npx != nil {
            badges.append("NPX")
        }
        if agent.distribution.uvx != nil {
            badges.append("UVX")
        }
        return badges
    }
}
