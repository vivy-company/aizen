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
    @StateObject private var viewModel: SessionsListStore
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    private var surfaceColor: Color {
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
    
    private var headerView: some View {
        HStack(spacing: 12) {
            Text("Sessions")
                .font(.headline)

            if !viewModel.sessions.isEmpty {
                TagBadge(text: "\(viewModel.sessions.count)", color: .secondary, cornerRadius: 6)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(surfaceColor)
    }

    private var agentFilterMenu: some View {
        Menu {
            Button {
                viewModel.selectedAgentName = nil
            } label: {
                Label("All Agents", systemImage: "person.2")
            }

            if !viewModel.availableAgents.isEmpty {
                Divider()
            }

            ForEach(viewModel.availableAgents, id: \.self) { agentName in
                Button {
                    viewModel.selectedAgentName = agentName
                } label: {
                    HStack(spacing: 8) {
                        AgentIconView(agent: agentName, size: 14)
                        Text(agentName)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                if let selectedAgent = viewModel.selectedAgentName {
                    AgentIconView(agent: selectedAgent, size: 14)
                } else {
                    Image(systemName: "person.2")
                        .font(.system(size: 12))
                }

                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(viewModel.availableAgents.isEmpty)
    }
    
    private var contentView: some View {
        Group {
            if viewModel.isLoading && viewModel.sessions.isEmpty {
                loadingState
            } else if viewModel.sessions.isEmpty {
                emptyState
            } else {
                sessionsList
            }
        }
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
            Text("Loading sessions...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No Sessions")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Chat sessions will appear here")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var sessionsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.sessions, id: \.id) { session in
                    SessionRowView(session: session)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewModel.resumeSession(session)
                            dismiss()
                        }
                        .onAppear {
                            viewModel.loadMoreIfNeeded(for: session)
                        }
                        .contextMenu {
                            sessionContextMenu(for: session)
                        }

                    Divider()
                }
            }
        }
    }
    
    @ViewBuilder
    private func sessionContextMenu(for session: ChatSession) -> some View {
        Button {
            viewModel.resumeSession(session)
            dismiss()
        } label: {
            Label("Resume Session", systemImage: "play.fill")
        }
        
        Divider()
        
        if session.archived {
            Button {
                viewModel.unarchiveSession(session, context: viewContext)
            } label: {
                Label("Unarchive", systemImage: "tray.and.arrow.up")
            }
        } else {
            Button {
                viewModel.archiveSession(session, context: viewContext)
            } label: {
                Label("Archive", systemImage: "archivebox")
            }
        }
        
        Divider()
        
        Button(role: .destructive) {
            viewModel.deleteSession(session, context: viewContext)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
    
}

#Preview {
    SessionsListView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
