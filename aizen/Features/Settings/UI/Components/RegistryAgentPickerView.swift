//
//  RegistryAgentPickerView.swift
//  aizen
//

import ACPRegistry
import SwiftUI

struct RegistryAgentPickerView: View {
    @State var searchText = ""
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

}
