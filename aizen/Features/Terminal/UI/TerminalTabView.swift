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
