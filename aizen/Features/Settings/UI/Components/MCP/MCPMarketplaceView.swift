//
//  MCPMarketplaceView.swift
//  aizen
//
//  Marketplace for browsing and installing MCP servers
//

import ACP
import Foundation
import SwiftUI

struct MCPMarketplaceView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var mcpManager = MCPManagementStore.shared

    let agentId: String
    let agentPath: String?
    let agentName: String

    @State var searchQuery = ""
    @State var servers: [MCPServer] = []
    @State var isLoading = true
    @State var hasMore = false
    @State var nextCursor: String?
    @State var errorMessage: String?
    @State var selectedFilter: ServerFilter = .all

    @State var selectedServer: MCPServer?
    @State var showingInstallSheet = false
    @State var serverToRemove: MCPServer?
    @State var showingRemoveConfirmation = false

    @State var supportedTransports: Set<String> = ["stdio"]

    enum ServerFilter: String, CaseIterable {
        case all = "All"
        case installed = "Added"
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

    private var surfaceColor: Color {
        AppSurfaceTheme.backgroundColor(colorScheme: colorScheme)
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
        .settingsSheetChrome()
        .task {
            await loadTransportSupport()
            await mcpManager.syncInstalled(agentId: agentId)
        }
        .task(id: searchQuery) {
            await updateSearchResults(for: searchQuery)
        }
        .sheet(isPresented: $showingInstallSheet) {
            if let server = selectedServer {
                MCPInstallConfigSheet(
                    server: server,
                    agentId: agentId,
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
                Text("Remove \(server.displayName) from Aizen's MCP defaults for \(agentName)?")
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
                onSubmit: {
                    Task { await searchImmediately() }
                },
                onClear: {
                    searchQuery = ""
                },
                trailing: { EmptyView() }
            )
            .padding(8)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(8)

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
        .background(surfaceColor)
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

    // MARK: - Data Loading

    func loadServers() async {
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

        let launchArgs = AgentRegistry.shared.getAgentLaunchArgs(for: agentId)
        let launchEnvironment = await AgentRegistry.shared.resolvedAgentLaunchEnvironment(for: agentId)
        let tempClient = Client()

        do {
            try await tempClient.launch(
                agentPath: path,
                arguments: launchArgs,
                environment: launchEnvironment.isEmpty ? nil : launchEnvironment
            )
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

    func isCompatible(server: MCPServer) -> Bool {
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

    private func searchImmediately() async {
        await updateSearchResults(for: searchQuery, debounce: false)
    }

    private func updateSearchResults(for query: String, debounce: Bool = true) async {
        let trimmedQuery = query.trimmingCharacters(in: .whitespaces)

        guard !trimmedQuery.isEmpty else {
            await loadServers()
            return
        }

        if debounce {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            guard searchQuery == query else { return }
        }

        isLoading = true
        errorMessage = nil

        print("[MCPMarketplace] Searching for: \(query)")

        do {
            let result = try await MCPRegistryService.shared.search(query: query, limit: 50)
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

    func loadMore() async {
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
            try await mcpManager.remove(serverName: serverName, agentId: agentId)
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
