//
//  SessionsListView.swift
//  aizen
//
//  SwiftUI view for displaying and managing chat sessions
//

import SwiftUI
import CoreData

struct SessionsListView: View {
    @StateObject private var viewModel = SessionsListViewModel()
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @FetchRequest private var sessions: FetchedResults<ChatSession>
    
    init() {
        let request = SessionsListViewModel().buildFetchRequest()
        _sessions = FetchRequest(fetchRequest: request)
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                filterToolbar
                
                if sessions.isEmpty {
                    emptyState
                } else {
                    sessionsList
                }
            }
            .navigationTitle("Chat Sessions")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 800, height: 600)
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
        .onChange(of: viewModel.selectedFilter) { _, _ in updateFetchRequest() }
        .onChange(of: viewModel.searchText) { _, _ in updateFetchRequest() }
        .onChange(of: viewModel.selectedWorktreeId) { _, _ in updateFetchRequest() }
    }
    
    private var filterToolbar: some View {
        HStack {
            Picker("Filter", selection: $viewModel.selectedFilter) {
                ForEach(SessionsListViewModel.SessionFilter.allCases, id: \.self) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 300)
            
            Spacer()
            
            SearchField(
                placeholder: "Search sessions...",
                text: $viewModel.searchText,
                trailing: { EmptyView() }
            )
            .frame(width: 200)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
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
        List {
            ForEach(sessions, id: \.id) { session in
                SessionRowView(session: session)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.resumeSession(session)
                        dismiss()
                    }
                    .contextMenu {
                        sessionContextMenu(for: session)
                    }
            }
        }
        .listStyle(.inset)
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
    
    private func updateFetchRequest() {
        sessions.nsPredicate = viewModel.buildFetchRequest().predicate
    }
}

struct SessionRowView: View {
    let session: ChatSession
    
    private static let timestampFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
    
    private var relativeTimestamp: String {
        guard let lastMessage = session.lastMessageAt else {
            return "No messages"
        }
        return Self.timestampFormatter.localizedString(for: lastMessage, relativeTo: Date())
    }
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(session.title ?? "Untitled")
                        .font(.headline)
                    
                    if session.archived {
                        Image(systemName: "archivebox.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                HStack(spacing: 8) {
                    Text(session.agentName ?? "Unknown Agent")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .foregroundColor(.secondary)
                    
                    Text("\(session.messageCount) messages")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    if let worktreeName = session.worktree?.branch {
                        Text("•")
                            .foregroundColor(.secondary)
                        
                        Text(worktreeName)
                            .font(.subheadline)
                            .foregroundColor(.blue)
                    }
                }
            }
            
            Spacer()
            
            Text(relativeTimestamp)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    SessionsListView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
