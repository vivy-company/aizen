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
    @StateObject private var viewModel: SessionsListViewModel
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    private var surfaceColor: Color {
        Color(nsColor: .windowBackgroundColor)
    }

    init(worktreeId: UUID? = nil) {
        let vm = SessionsListViewModel(worktreeId: worktreeId)
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
                    Label("All", systemImage: "square.grid.2x2").tag(SessionsListViewModel.SessionFilter.all)
                    Label("Active", systemImage: "bolt.fill").tag(SessionsListViewModel.SessionFilter.active)
                    Label("Archived", systemImage: "archivebox").tag(SessionsListViewModel.SessionFilter.archived)
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
        .task {
            await viewModel.reloadSessions(in: viewContext)
        }
        .onChange(of: viewModel.selectedFilter) { _, _ in
            Task { await viewModel.reloadSessions(in: viewContext) }
        }
        .onChange(of: viewModel.searchText) { _, _ in
            Task { await viewModel.reloadSessions(in: viewContext) }
        }
        .onChange(of: viewModel.selectedWorktreeId) { _, _ in
            Task { await viewModel.reloadSessions(in: viewContext) }
        }
        .onChange(of: viewModel.selectedAgentName) { _, _ in
            Task { await viewModel.reloadSessions(in: viewContext) }
        }
        .onChange(of: viewModel.fetchLimit) { _, _ in
            Task { await viewModel.reloadSessions(in: viewContext) }
        }
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

struct SessionRowView: View {
    let session: ChatSession
    
    @State private var cachedSummary: String = ""
    @State private var isHovered = false
    
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

    private var agentName: String {
        let name = session.agentName ?? ""
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? SessionsListViewModel.unknownAgentLabel : trimmed
    }

    private var sessionTitle: String {
        if !cachedSummary.isEmpty {
            return cachedSummary
        }
        if let title = session.title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return title
        }
        return "Untitled Session"
    }

    private func computeSessionSummary() -> String {
        // Use most recent user message for summary
        guard let messages = session.messages as? Set<ChatMessage> else {
            return "No messages yet"
        }

        let sortedMessages = messages
            .filter { $0.role == "user" }
            .sorted { (m1, m2) -> Bool in
                let t1 = m1.timestamp ?? Date.distantPast
                let t2 = m2.timestamp ?? Date.distantPast
                return t1 > t2
            }

        guard let latestMessage = sortedMessages.first,
              let contentJSON = latestMessage.contentJSON else {
            return "No user messages yet"
        }
        
        // Extract text from contentJSON
        guard let contentData = contentJSON.data(using: .utf8) else {
            return "Unable to load message"
        }
        
        guard let contentBlocks = try? JSONDecoder().decode([ContentBlock].self, from: contentData) else {
            return contentJSON
        }
        
        var textParts: [String] = []
        for block in contentBlocks {
            if case .text(let textContent) = block {
                textParts.append(textContent.text)
            }
        }
        
        let text = textParts.joined(separator: " ")
        
        if text.isEmpty {
            return "Empty message"
        }
        
        // Truncate to reasonable length
        let maxLength = 120
        if text.count > maxLength {
            let truncated = String(text.prefix(maxLength))
            return truncated + "..."
        }
        
        return text
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AgentIconView(agent: session.agentName ?? "claude", size: 18)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(sessionTitle)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer()

                    Text(relativeTimestamp)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 8) {
                    Text(agentName)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    if session.archived {
                        TagBadge(text: "Archived", color: .orange, cornerRadius: 4, backgroundOpacity: 0.2)
                    }

                    Text("•")
                        .foregroundStyle(.quaternary)

                    Text("\(session.messageCount) messages")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    if let worktreeName = session.worktree?.branch {
                        Text("•")
                            .foregroundStyle(.quaternary)

                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: 10))
                            Text(worktreeName)
                        }
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                    }

                    if let createdAt = session.createdAt {
                        Text("•")
                            .foregroundStyle(.quaternary)

                        Text("Created \(createdAt, formatter: Self.dateFormatter)")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .modifier(SelectableRowModifier(
            isSelected: false,
            isHovered: isHovered,
            showsIdleBackground: false,
            cornerRadius: 0
        ))
        .onHover { hovering in
            isHovered = hovering
        }
        .task(id: session.id) {
            cachedSummary = computeSessionSummary()
        }
    }
    
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}

#Preview {
    SessionsListView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
