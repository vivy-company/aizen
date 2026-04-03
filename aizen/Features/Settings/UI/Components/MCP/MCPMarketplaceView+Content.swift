import SwiftUI

extension MCPMarketplaceView {
    var filteredServers: [MCPServer] {
        let compatibleServers = servers.filter { isCompatible(server: $0) }
        switch selectedFilter {
        case .all:
            return compatibleServers
        case .installed:
            return []
        case .remote:
            return compatibleServers.filter { $0.isRemoteOnly }
        case .package:
            return compatibleServers.filter { !$0.isRemoteOnly }
        }
    }

    @ViewBuilder
    var contentView: some View {
        Group {
            if selectedFilter == .installed {
                installedServerListView
            } else if isLoading && servers.isEmpty {
                loadingView
            } else if let error = errorMessage {
                errorView(error)
            } else if filteredServers.isEmpty {
                emptyView
            } else {
                serverListView
            }
        }
    }

    var loadingView: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text("Loading MCP servers...")
                .font(.callout)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    func errorView(_ error: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundColor(.orange)
            Text(error)
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await loadServers() }
            }
            .buttonStyle(.bordered)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    var emptyView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: selectedFilter == .installed ? "checkmark.circle" : "magnifyingglass")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            Text(emptyMessage)
                .font(.callout)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    var emptyMessage: String {
        if selectedFilter != .installed, !servers.isEmpty, filteredServers.isEmpty {
            return "No compatible servers for \(agentName)"
        }
        switch selectedFilter {
        case .installed:
            return "No MCP servers added"
        case .remote:
            return "No remote servers found"
        case .package:
            return "No package servers found"
        case .all:
            return searchQuery.isEmpty ? "No servers available" : "No servers found"
        }
    }

    var installedServers: [MCPInstalledServer] {
        mcpManager.servers(for: agentId)
    }

    var installedServerListView: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(installedServers.count) added")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if mcpManager.isSyncingServers(for: agentId) {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.leading, 4)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            if installedServers.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("No MCP servers added")
                        .font(.callout)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach(installedServers) { server in
                        MCPInstalledServerRow(server: server) {
                            Task {
                                do {
                                    try await mcpManager.remove(
                                        serverName: server.serverName,
                                        agentId: agentId
                                    )
                                } catch {
                                    errorMessage = error.localizedDescription
                                }
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    var serverListView: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(filteredServers.count) servers")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.leading, 4)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            List {
                ForEach(filteredServers) { server in
                    MCPServerRowView(
                        server: server,
                        isInstalled: mcpManager.isInstalled(
                            serverName: server.name,
                            agentId: agentId
                        ),
                        onInstall: {
                            selectedServer = server
                            showingInstallSheet = true
                        },
                        onRemove: {
                            serverToRemove = server
                            showingRemoveConfirmation = true
                        }
                    )
                    .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
                }

                if hasMore && selectedFilter != .installed {
                    Button {
                        Task { await loadMore() }
                    } label: {
                        HStack {
                            Spacer()
                            if isLoading {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text("Load more servers")
                                    .font(.caption)
                                    .foregroundColor(.accentColor)
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .disabled(isLoading)
                }
            }
            .listStyle(.plain)
        }
    }
}
