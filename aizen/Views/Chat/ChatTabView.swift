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
    @State private var cachedSessionIds: [UUID] = []
    private let maxCachedSessions = 10

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
            animation: nil
        )
    }

    var body: some View {
        if sessions.isEmpty {
            chatEmptyState
        } else {
            ZStack {
                ForEach(cachedSessions) { session in
                    let isSelected = selectedSessionId == session.id
                    ChatSessionView(
                        worktree: worktree,
                        session: session,
                        sessionManager: sessionManager,
                        viewContext: viewContext,
                        isSelected: isSelected
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(isSelected ? 1 : 0)
                    .allowsHitTesting(isSelected)
                    .zIndex(isSelected ? 1 : 0)
                }
            }
            .onAppear {
                syncSelectionAndCache()
            }
            .onChange(of: selectedSessionId) { _ in
                updateCacheForSelection()
            }
            .onChange(of: sessions.count) { _ in
                syncSelectionAndCache()
            }
        }
    }

    private var cachedSessions: [ChatSession] {
        if cachedSessionIds.isEmpty {
            let fallbackId = selectedSessionId ?? sessions.last?.id
            if let fallbackId,
               let fallback = sessions.first(where: { $0.id == fallbackId }) {
                return [fallback]
            }
            if let last = sessions.last {
                return [last]
            }
        }
        return cachedSessionIds.compactMap { id in
            sessions.first(where: { $0.id == id })
        }
    }

    private func syncSelectionAndCache() {
        if selectedSessionId == nil {
            selectedSessionId = sessions.last?.id
        } else if let currentId = selectedSessionId,
                  !sessions.contains(where: { $0.id == currentId }) {
            selectedSessionId = sessions.last?.id
        }
        pruneCache()
        updateCacheForSelection()
    }

    private func updateCacheForSelection() {
        guard let selectedId = selectedSessionId else { return }
        guard sessions.contains(where: { $0.id == selectedId }) else { return }
        cachedSessionIds.removeAll { $0 == selectedId }
        cachedSessionIds.append(selectedId)
        if cachedSessionIds.count > maxCachedSessions {
            cachedSessionIds.removeFirst(cachedSessionIds.count - maxCachedSessions)
        }
    }

    private func pruneCache() {
        let validIds = Set(sessions.compactMap { $0.id })
        cachedSessionIds.removeAll { !validIds.contains($0) }
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
