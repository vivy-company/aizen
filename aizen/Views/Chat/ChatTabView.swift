//
//  ChatTabView.swift
//  aizen
//
//  Chat tab management and empty state
//

import SwiftUI
import CoreData

struct ChatTabView: View {
    let worktree: Worktree
    @Binding var selectedSessionId: UUID?

    private let sessionManager = ChatSessionManager.shared

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
                        sessionManager: sessionManager
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

            HStack(spacing: 12) {
                ForEach(AgentRegistry.shared.availableAgents.prefix(3), id: \.self) { agent in
                    Button {
                        createNewSession(withAgent: agent)
                    } label: {
                        VStack(spacing: 8) {
                            AgentIconView(agent: agent, size: 12)
                            Text(agent.capitalized)
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
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func createNewSession(withAgent agent: String) {
        guard let context = worktree.managedObjectContext else { return }

        let session = ChatSession(context: context)
        session.id = UUID()
        session.title = agent.capitalized
        session.agentName = agent
        session.createdAt = Date()
        session.worktree = worktree

        do {
            try context.save()
            selectedSessionId = session.id
        } catch {
            print("Failed to create chat session: \(error)")
        }
    }
}
