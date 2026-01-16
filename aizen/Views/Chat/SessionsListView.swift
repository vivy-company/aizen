//
//  SessionsListView.swift
//  aizen
//
//  SwiftUI view for displaying and managing chat sessions
//

import SwiftUI
import CoreData

struct SessionsListView: View {
    @StateObject private var viewModel: SessionsListViewModel
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @FetchRequest private var sessions: FetchedResults<ChatSession>
    
    init(worktreeId: UUID? = nil) {
        let vm = SessionsListViewModel(worktreeId: worktreeId)
        _viewModel = StateObject(wrappedValue: vm)
        let request = vm.buildFetchRequest()
        _sessions = FetchRequest(fetchRequest: request)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            filterToolbar
            
            if sessions.isEmpty {
                emptyState
            } else {
                sessionsList
            }
        }
        .frame(minWidth: 700, idealWidth: 900, maxWidth: .infinity, minHeight: 500, idealHeight: 650, maxHeight: .infinity)
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
        .onChange(of: viewModel.fetchLimit) { _, _ in updateFetchRequest() }
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
            
            if sessions.count >= viewModel.fetchLimit {
                HStack {
                    Spacer()
                    Button("Load More") {
                        viewModel.loadMore()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                    .padding(.vertical, 8)
                    Spacer()
                }
                .listRowSeparator(.hidden)
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
    
    @Environment(\.managedObjectContext) private var viewContext
    @State private var cachedSummary: String = ""
    
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
    
    private func computeSessionSummary() -> String {
        // Get first user message for summary
        guard let messages = session.messages as? Set<ChatMessage> else {
            return "No messages yet"
        }
        
        let sortedMessages = messages
            .filter { $0.role == "user" }
            .sorted { (m1, m2) -> Bool in
                let t1 = m1.timestamp ?? Date.distantPast
                let t2 = m2.timestamp ?? Date.distantPast
                return t1 < t2
            }
        
        guard let firstMessage = sortedMessages.first,
              let contentJSON = firstMessage.contentJSON else {
            return "Waiting for first message..."
        }
        
        // Extract text from contentJSON
        guard let contentData = contentJSON.data(using: .utf8) else {
            return "Unable to load message"
        }
        
        guard let content = try? JSONDecoder().decode([MessageContent].self, from: contentData) else {
            return "Unable to parse message"
        }
        
        var textParts: [String] = []
        for item in content {
            if case .text(let textContent) = item {
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
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Text(session.agentName ?? "Unknown Agent")
                    .font(.headline)
                
                if session.archived {
                    Image(systemName: "archivebox.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Text("•")
                    .foregroundColor(.secondary)
                
                Text(cachedSummary)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                Spacer()
                
                Text(relativeTimestamp)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack(spacing: 8) {
                Text("\(session.messageCount) messages")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if let worktreeName = session.worktree?.branch {
                    Text("•")
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.caption2)
                        Text(worktreeName)
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
                
                if let createdAt = session.createdAt {
                    Text("•")
                        .foregroundColor(.secondary)
                    
                    Text("Created \(createdAt, formatter: Self.dateFormatter)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 6)
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

// Helper for decoding message content
private enum MessageContent: Decodable {
    case text(MessageTextContent)
    case toolUse(MessageToolUseContent)
    case toolResult(MessageToolResultContent)
    
    private enum CodingKeys: String, CodingKey {
        case type
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        switch type {
        case "text":
            self = .text(try MessageTextContent(from: decoder))
        case "tool_use":
            self = .toolUse(try MessageToolUseContent(from: decoder))
        case "tool_result":
            self = .toolResult(try MessageToolResultContent(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown type: \(type)")
        }
    }
}

private struct MessageTextContent: Decodable {
    let type: String
    let text: String
}

private struct MessageToolUseContent: Decodable {
    let type: String
    let id: String
    let name: String
}

private struct MessageToolResultContent: Decodable {
    let type: String
    let tool_use_id: String
}

#Preview {
    SessionsListView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
