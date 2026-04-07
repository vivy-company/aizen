//
//  TerminalTabView.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import ACP
import os.log
import SwiftUI

struct TerminalTabView: View {
    @ObservedObject var worktree: Worktree
    @Binding var selectedSessionId: UUID?
    @ObservedObject var repositoryManager: WorkspaceRepositoryStore
    @Environment(\.colorScheme) var colorScheme

    private let sessionManager = TerminalRuntimeStore.shared
    @StateObject var presetManager = TerminalPresetStore.shared
    let logger = Logger.terminal
    let visiblePresetsLimit = 8
    let emptyStateMaxWidth: CGFloat = 540

    var sessions: [TerminalSession] {
        let sessions = (worktree.terminalSessions as? Set<TerminalSession>) ?? []
        return sessions
            .filter { !$0.isDeleted }
            .sorted { ($0.createdAt ?? Date()) < ($1.createdAt ?? Date()) }
    }

    // Derive valid selection declaratively
    private var validatedSelectedSessionId: UUID? {
        // If current selection is valid, use it
        if let currentId = selectedSessionId,
           sessions.contains(where: { $0.id == currentId }) {
            return currentId
        }
        // Otherwise, select first or last session if available
        return sessions.last?.id ?? sessions.first?.id
    }

    private var selectedSessions: [TerminalSession] {
        guard let selectedId = validatedSelectedSessionId else { return [] }
        return sessions.filter { $0.id == selectedId }
    }

    var body: some View {
        if sessions.isEmpty {
            terminalEmptyState
        } else {
            ForEach(selectedSessions) { session in
                SplitTerminalView(
                    worktree: worktree,
                    session: session,
                    sessionManager: sessionManager,
                    isSelected: true
                )
                .id(session.objectID)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task {
                // Sync binding once with validated value
                if selectedSessionId != validatedSelectedSessionId {
                    selectedSessionId = validatedSelectedSessionId
                }
            }
        }
    }
}

#Preview {
    TerminalTabView(
        worktree: Worktree(),
        selectedSessionId: .constant(nil),
        repositoryManager: WorkspaceRepositoryStore(viewContext: PersistenceController.preview.container.viewContext)
    )
}
