//
//  MCPMarketplaceView.swift
//  aizen
//
//  Marketplace for browsing and installing MCP servers
//

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
