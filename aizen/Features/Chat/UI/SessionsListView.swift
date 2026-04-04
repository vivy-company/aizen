//
//  SessionsListView.swift
//  aizen
//
//  SwiftUI view for displaying and managing chat sessions
//

import ACP
import CoreData
import SwiftUI

struct SessionsListView: View {
    @StateObject var viewModel: SessionsListStore
    @Environment(\.managedObjectContext) var viewContext
    @Environment(\.dismiss) var dismiss
    
    var surfaceColor: Color {
        AppSurfaceTheme.backgroundColor()
    }

    init(worktreeId: UUID? = nil) {
        let vm = SessionsListStore(worktreeId: worktreeId)
        _viewModel = StateObject(wrappedValue: vm)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            contentView
        }
        .frame(minWidth: 700, idealWidth: 900, maxWidth: .infinity, minHeight: 500, idealHeight: 650, maxHeight: .infinity)
        .background(surfaceColor)
        .toolbarBackground(surfaceColor, for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Picker("", selection: $viewModel.selectedFilter) {
                    Label("All", systemImage: "square.grid.2x2").tag(SessionsListStore.SessionFilter.all)
                    Label("Active", systemImage: "bolt.fill").tag(SessionsListStore.SessionFilter.active)
                    Label("Archived", systemImage: "archivebox").tag(SessionsListStore.SessionFilter.archived)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            ToolbarItem(placement: .navigation) {
                Spacer().frame(width: 12)
            }

            ToolbarItem(placement: .navigation) {
                agentFilterMenu
            }
        }
        .searchable(text: $viewModel.searchText, placement: .toolbar, prompt: "Search sessions")
        .alert("Error", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
            }
        }
        .task(id: reloadKey) {
            await viewModel.reloadSessions(in: viewContext)
        }
    }

    private var reloadKey: ReloadKey {
        ReloadKey(
            selectedFilter: viewModel.selectedFilter,
            searchText: viewModel.searchText,
            selectedWorktreeId: viewModel.selectedWorktreeId,
            selectedAgentName: viewModel.selectedAgentName,
            fetchLimit: viewModel.fetchLimit
        )
    }

    private struct ReloadKey: Hashable {
        let selectedFilter: SessionsListStore.SessionFilter
        let searchText: String
        let selectedWorktreeId: UUID?
        let selectedAgentName: String?
        let fetchLimit: Int
    }
}

#Preview {
    SessionsListView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
