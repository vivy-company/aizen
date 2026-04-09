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
    let sessions: [TerminalSession]
    let isVisible: Bool
    @Binding var selectedSessionId: UUID?
    @ObservedObject var repositoryManager: WorkspaceRepositoryStore
    @Environment(\.colorScheme) var colorScheme

    private let sessionManager = TerminalRuntimeStore.shared
    @StateObject var presetManager = TerminalPresetStore.shared
    let logger = Logger.terminal
    let visiblePresetsLimit = 8
    let emptyStateMaxWidth: CGFloat = 540
    @State var cachedSessionIds: [UUID] = []
    let maxCachedSessions = 3

    var body: some View {
        if sessions.isEmpty {
            terminalEmptyState
        } else {
            ZStack {
                ForEach(cachedSessions) { session in
                    SplitTerminalView(
                        worktree: worktree,
                        session: session,
                        sessionManager: sessionManager,
                        isSelected: isVisible && session.id == validatedSelectedSessionId
                    )
                    .id(session.objectID)
                    .opacity(session.id == validatedSelectedSessionId ? 1 : 0)
                    .allowsHitTesting(session.id == validatedSelectedSessionId)
                    .accessibilityHidden(session.id != validatedSelectedSessionId)
                    .zIndex(session.id == validatedSelectedSessionId ? 1 : 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task {
                syncSelectionAndCache()
            }
            .task(id: selectedSessionId) {
                syncSelectionAndCache()
            }
            .task(id: sessionIdentitySnapshot) {
                syncSelectionAndCache()
            }
            .task(id: isVisible) {
                syncSelectionAndCache()
            }
        }
    }
}

#Preview {
    TerminalTabView(
        worktree: Worktree(),
        sessions: [],
        isVisible: true,
        selectedSessionId: .constant(nil),
        repositoryManager: WorkspaceRepositoryStore(viewContext: PersistenceController.preview.container.viewContext)
    )
}
