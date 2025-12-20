//
//  ChatTabView.swift
//  aizen
//
//  Chat tab management and empty state
//

import SwiftUI
import CoreData
import os.log

struct ChatTabView: View {
    let worktree: Worktree
    @Binding var selectedSessionId: UUID?

    @Environment(\.managedObjectContext) private var viewContext
    private let sessionManager = ChatSessionManager.shared
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen", category: "ChatTabView")
    @State private var enabledAgents: [AgentMetadata] = []

    @FetchRequest private var sessions: FetchedResults<ChatSession>

    init(worktree: Worktree, selectedSessionId: Binding<UUID?>) {
        self.worktree = worktree
        self._selectedSessionId = selectedSessionId

        // Handle deleted worktree gracefully - use impossible predicate to return empty results
        let predicate: NSPredicate
        if let worktreeId = worktree.id {
            predicate = NSPredicate(format: "worktree.id == %@", worktreeId as CVarArg)
        } else {
            predicate = NSPredicate(value: false)
        }

        self._sessions = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \ChatSession.createdAt, ascending: true)],
            predicate: predicate,
            animation: .default
        )
    }

    var body: some View {
        if sessions.isEmpty {
            chatEmptyState
        } else if let session = selectedSession ?? sessions.last {
            ChatSessionView(
                worktree: worktree,
                session: session,
                sessionManager: sessionManager,
                viewContext: viewContext
            )
            .id(session.objectID)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.2), value: selectedSessionId)
            .onAppear {
                if selectedSessionId == nil {
                    selectedSessionId = sessions.first?.id
                }
            }
            .onChange(of: sessions.count) { _ in
                // Validate that selectedSessionId exists in current sessions
                // If not, select the most recent session
                if let currentId = selectedSessionId,
                   !sessions.contains(where: { $0.id == currentId }) {
                    selectedSessionId = sessions.last?.id
                } else if selectedSessionId == nil {
                    selectedSessionId = sessions.last?.id
                }
            }
        }
    }

    private var selectedSession: ChatSession? {
        guard let currentId = selectedSessionId else { return nil }
        return sessions.first(where: { $0.id == currentId })
    }

    private var chatEmptyState: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "message.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.secondary)

                VStack(spacing: 8) {
                    Text("chat.noChatSessions", bundle: .main)
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("chat.startConversation", bundle: .main)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }

            // Responsive layout: row if <=5 agents, column if >5
            if enabledAgents.count <= 5 {
                HStack(spacing: 12) {
                    ForEach(enabledAgents, id: \.id) { agentMetadata in
                        agentButton(for: agentMetadata)
                    }
                }
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(100), spacing: 12), count: 3), spacing: 12) {
                    ForEach(enabledAgents, id: \.id) { agentMetadata in
                        agentButton(for: agentMetadata)
                    }
                }
                .padding(.horizontal, 20)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            loadEnabledAgents()
        }
        .onReceive(NotificationCenter.default.publisher(for: .agentMetadataDidChange)) { _ in
            loadEnabledAgents()
        }
    }

    @ViewBuilder
    private func agentButton(for agentMetadata: AgentMetadata) -> some View {
        Button {
            createNewSession(withAgent: agentMetadata.id)
        } label: {
            VStack(spacing: 8) {
                AgentIconView(metadata: agentMetadata, size: 12)
                Text(agentMetadata.name)
                    .font(.system(size: 13, weight: .medium))
            }
            .frame(width: 100, height: 80)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.separator.opacity(0.3), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func loadEnabledAgents() {
        Task {
            enabledAgents = AgentRegistry.shared.getEnabledAgents()
        }
    }

    private func createNewSession(withAgent agent: String) {
        guard let context = worktree.managedObjectContext else { return }

        let session = ChatSession(context: context)
        session.id = UUID()
        session.agentName = agent
        session.createdAt = Date()
        session.worktree = worktree

        // Use agent display name instead of ID
        let displayName = AgentRegistry.shared.getMetadata(for: agent)?.name ?? agent.capitalized
        session.title = displayName

        do {
            try context.save()
            // Update binding immediately (synchronous post-save)
            selectedSessionId = session.id
            logger.info("Created new chat session: \(session.id?.uuidString ?? "unknown")")
        } catch {
            logger.error("Failed to create chat session: \(error.localizedDescription)")
        }
    }
}
