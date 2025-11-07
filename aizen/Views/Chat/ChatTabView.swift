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

    var sessions: [ChatSession] {
        let sessions = (worktree.chatSessions as? Set<ChatSession>) ?? []
        return sessions.sorted { ($0.createdAt ?? Date()) < ($1.createdAt ?? Date()) }
    }

    var body: some View {
        if sessions.isEmpty {
            chatEmptyState
        } else {
            ZStack {
                ForEach(sessions) { session in
                    ChatSessionView(
                        worktree: worktree,
                        session: session,
                        sessionManager: sessionManager,
                        viewContext: viewContext
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(selectedSessionId == session.id ? 1 : 0)
                }
            }
            .onAppear {
                if selectedSessionId == nil {
                    selectedSessionId = sessions.first?.id
                }
            }
        }
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
            enabledAgents = await AgentRegistry.shared.getEnabledAgents()
        }
    }

    private func createNewSession(withAgent agent: String) {
        guard let context = worktree.managedObjectContext else { return }

        let session = ChatSession(context: context)
        session.id = UUID()
        session.agentName = agent
        session.createdAt = Date()
        session.worktree = worktree

        Task {
            // Use agent display name instead of ID
            let displayName = AgentRegistry.shared.getMetadata(for: agent)?.name ?? agent.capitalized
            await MainActor.run {
                session.title = displayName
                do {
                    try context.save()
                    selectedSessionId = session.id
                } catch {
                    logger.error("Failed to create chat session: \(error.localizedDescription)")
                }
            }
        }
    }
}
