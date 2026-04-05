//
//  MCPMarketplaceView.swift
//  aizen
//
//  Marketplace for browsing and installing MCP servers
//

import Foundation
import SwiftUI

struct MCPMarketplaceView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
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
