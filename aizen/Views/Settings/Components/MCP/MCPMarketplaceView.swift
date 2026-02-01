//
//  MCPMarketplaceView.swift
//  aizen
//
//  Marketplace for browsing and installing MCP servers
//

import ACP
import Combine
import Foundation
import SwiftUI

struct MCPMarketplaceView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var mcpManager = MCPManager.shared

    let agentId: String
    let agentPath: String?
    let agentName: String

    @State private var searchQuery = ""
    @State private var servers: [MCPServer] = []
    @State private var isLoading = true
    @State private var hasMore = false
    @State private var nextCursor: String?
    @State private var errorMessage: String?
    @State private var selectedFilter: ServerFilter = .all

    @State private var selectedServer: MCPServer?
    @State private var showingInstallSheet = false
    @State private var serverToRemove: MCPServer?
    @State private var showingRemoveConfirmation = false

    @State private var searchTask: Task<Void, Never>?
    @State private var supportedTransports: Set<String> = ["stdio"]

    private enum ServerFilter: String, CaseIterable {
        case all = "All"
        case installed = "Installed"
        case remote = "Remote"
        case package = "Package"

        var icon: String {
            switch self {
            case .all: return "square.grid.2x2"
            case .installed: return "checkmark.circle"
            case .remote: return "globe"
            case .package: return "shippingbox"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            filterTabsView
            Divider()
            contentView
        }
        .frame(width: 600, height: 520)
        .background(Color(NSColor.windowBackgroundColor))
        .task {
            await loadTransportSupport()
            await mcpManager.syncInstalled(agentId: agentId, agentPath: agentPath)
            await loadServers()
        }
        .sheet(isPresented: $showingInstallSheet) {
            if let server = selectedServer {
                MCPInstallConfigSheet(
                    server: server,
                    agentId: agentId,
                    agentPath: agentPath,
                    agentName: agentName,
                    onInstalled: {
                        selectedServer = nil
                    }
                )
            }
        }
        .alert("Remove Server", isPresented: $showingRemoveConfirmation) {
            Button("Cancel", role: .cancel) {
                serverToRemove = nil
            }
            Button("Remove", role: .destructive) {
                if let server = serverToRemove {
                    Task { await removeServer(server) }
                }
            }
        } message: {
            if let server = serverToRemove {
                Text("Remove \(server.displayName) from \(agentName)?")
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 12) {
            SearchField(
                placeholder: "Search MCP servers...",
                text: $searchQuery,
                iconColor: .secondary,
                onSubmit: { Task { await search() } },
                onClear: {
                    searchTask?.cancel()
                    Task { await loadServers() }
                },
                trailing: { EmptyView() }
            )
            .padding(8)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(8)
            .onChange(of: searchQuery) { _, newValue in
                // Debounced search
                searchTask?.cancel()
                searchTask = Task {
                    try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce
                    guard !Task.isCancelled else { return }
                    await search()
                }
            }

            TagBadge(
                text: agentName,
                color: .accentColor,
                cornerRadius: 4,
                font: .caption,
                horizontalPadding: 8,
                verticalPadding: 4,
                backgroundOpacity: 0.15,
                textColor: .accentColor
            )

            Button("Done") {
                dismiss()
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Filter Tabs

    private var filterTabsView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(ServerFilter.allCases, id: \.self) { filter in
                    filterTab(filter)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }

    private func filterTab(_ filter: ServerFilter) -> some View {
        Button {
            selectedFilter = filter
        } label: {
            HStack(spacing: 4) {
                Image(systemName: filter.icon)
                    .font(.system(size: 11))
                Text(filter.rawValue)
                    .font(.system(size: 11, weight: selectedFilter == filter ? .semibold : .regular))

                if filter == .installed {
                    let count = mcpManager.servers(for: agentId).count
                    if count > 0 {
                        TagBadge(
                            text: "\(count)",
                            color: .accentColor,
                            font: .system(size: 10, weight: .medium),
                            horizontalPadding: 5,
                            verticalPadding: 1,
                            backgroundOpacity: 0.2
                        )
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                selectedFilter == filter ?
                Color.accentColor.opacity(0.15) :
                Color.clear
            )
            .foregroundColor(selectedFilter == filter ? .accentColor : .secondary)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Content

    private var filteredServers: [MCPServer] {
        let compatibleServers = servers.filter { isCompatible(server: $0) }
        switch selectedFilter {
        case .all:
            return compatibleServers
        case .installed:
            return [] // Handled separately by installedServerListView
        case .remote:
            return compatibleServers.filter { $0.isRemoteOnly }
        case .package:
            return compatibleServers.filter { !$0.isRemoteOnly }
        }
    }

    private var contentView: some View {
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

    private var loadingView: some View {
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

    private func errorView(_ error: String) -> some View {
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

    private var emptyView: some View {
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

    private var emptyMessage: String {
        if selectedFilter != .installed, !servers.isEmpty, filteredServers.isEmpty {
            return "No compatible servers for \(agentName)"
        }
        switch selectedFilter {
        case .installed:
            return "No MCP servers installed"
        case .remote:
            return "No remote servers found"
        case .package:
            return "No package servers found"
        case .all:
            return searchQuery.isEmpty ? "No servers available" : "No servers found"
        }
    }

    private var installedServers: [MCPInstalledServer] {
        mcpManager.servers(for: agentId)
    }

    private var installedServerListView: some View {
        VStack(spacing: 0) {
            // Count label
            HStack {
                Text("\(installedServers.count) installed")
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
                    Text("No MCP servers installed")
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
                                        agentId: agentId,
                                        agentPath: agentPath
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

    private var serverListView: some View {
        VStack(spacing: 0) {
            // Count label
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

            // Server list
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

                // Load more button
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

    // MARK: - Data Loading

    private func loadServers() async {
        isLoading = true
        errorMessage = nil

        print("[MCPMarketplace] Loading servers...")

        do {
            let result = try await MCPRegistryService.shared.listServers(limit: 50)
            let filtered = result.servers
                .map { $0.server }
                .filter { server in
                    (server.packages != nil && !server.packages!.isEmpty) ||
                    (server.remotes != nil && !server.remotes!.isEmpty)
                }
            // Deduplicate by name
            var seen = Set<String>()
            servers = filtered.filter { seen.insert($0.name).inserted }
            hasMore = result.metadata.hasMore
            nextCursor = result.metadata.nextCursor
            print("[MCPMarketplace] Loaded \(servers.count) servers, hasMore: \(hasMore)")
        } catch {
            print("[MCPMarketplace] Error loading servers: \(error)")
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func loadTransportSupport() async {
        await MainActor.run {
            supportedTransports = ["stdio"]
        }

        guard let path = agentPath,
              FileManager.default.isExecutableFile(atPath: path) else {
            return
        }

        let launchArgs = AgentRegistry.shared.getMetadata(for: agentId)?.launchArgs ?? []
        let tempClient = Client()

        do {
            try await tempClient.launch(agentPath: path, arguments: launchArgs)
            let capabilities = ClientCapabilities(
                fs: FileSystemCapabilities(
                    readTextFile: true,
                    writeTextFile: true
                ),
                terminal: true,
                meta: [
                    "terminal_output": AnyCodable(true),
                    "terminal-auth": AnyCodable(true)
                ]
            )

            let initResponse = try await tempClient.initialize(
                protocolVersion: 1,
                capabilities: capabilities
            )

            var transports: Set<String> = ["stdio"]
            if initResponse.agentCapabilities.mcpCapabilities?.http == true {
                transports.insert("http")
            }
            if initResponse.agentCapabilities.mcpCapabilities?.sse == true {
                transports.insert("sse")
            }

            await MainActor.run {
                supportedTransports = transports
            }
        } catch {
            // Keep stdio-only support on failure
        }
        await tempClient.terminate()
    }

    private func isCompatible(server: MCPServer) -> Bool {
        let packageSupported = server.packages?.contains { package in
            supportsTransport(package.transportType)
        } ?? false

        let remoteSupported = server.remotes?.contains { remote in
            supportsTransport(remote.type)
        } ?? false

        return packageSupported || remoteSupported
    }

    private func supportsTransport(_ type: String) -> Bool {
        switch type.lowercased() {
        case "stdio":
            return supportedTransports.contains("stdio")
        case "http", "streamable-http":
            return supportedTransports.contains("http")
        case "sse":
            return supportedTransports.contains("sse")
        default:
            return supportedTransports.contains(type.lowercased())
        }
    }

    private func search() async {
        guard !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty else {
            await loadServers()
            return
        }

        isLoading = true
        errorMessage = nil

        print("[MCPMarketplace] Searching for: \(searchQuery)")

        do {
            let result = try await MCPRegistryService.shared.search(query: searchQuery, limit: 50)
            let filtered = result.servers
                .map { $0.server }
                .filter { server in
                    (server.packages != nil && !server.packages!.isEmpty) ||
                    (server.remotes != nil && !server.remotes!.isEmpty)
                }
            // Deduplicate by name
            var seen = Set<String>()
            servers = filtered.filter { seen.insert($0.name).inserted }
            hasMore = result.metadata.hasMore
            nextCursor = result.metadata.nextCursor
            print("[MCPMarketplace] Found \(servers.count) servers")
        } catch {
            print("[MCPMarketplace] Search error: \(error)")
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func loadMore() async {
        guard let cursor = nextCursor, !isLoading else { return }

        isLoading = true

        print("[MCPMarketplace] Loading more with cursor: \(cursor)")

        do {
            let result: MCPSearchResult
            if searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                result = try await MCPRegistryService.shared.listServers(limit: 50, cursor: cursor)
            } else {
                result = try await MCPRegistryService.shared.search(query: searchQuery, limit: 50, cursor: cursor)
            }
            let newServers = result.servers
                .map { $0.server }
                .filter { server in
                    (server.packages != nil && !server.packages!.isEmpty) ||
                    (server.remotes != nil && !server.remotes!.isEmpty)
                }
            // Deduplicate - only add servers not already in list
            let existingNames = Set(servers.map { $0.name })
            let uniqueNew = newServers.filter { !existingNames.contains($0.name) }
            servers.append(contentsOf: uniqueNew)
            hasMore = result.metadata.hasMore
            nextCursor = result.metadata.nextCursor
            print("[MCPMarketplace] Added \(uniqueNew.count) more servers, total: \(servers.count)")
        } catch {
            print("[MCPMarketplace] Load more error: \(error)")
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func removeServer(_ server: MCPServer) async {
        let serverName = extractServerName(from: server.name)
        do {
            try await mcpManager.remove(serverName: serverName, agentId: agentId, agentPath: agentPath)
            serverToRemove = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func extractServerName(from fullName: String) -> String {
        if let lastComponent = fullName.split(separator: "/").last {
            return String(lastComponent)
        }
        return fullName
    }
}
