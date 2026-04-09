//
//  CompanionPanelView+Shell.swift
//  aizen
//

import SwiftUI

extension CompanionPanelView {
    private var terminalHostIdentity: String {
        let sessionIds = terminalSessions.compactMap { $0.id?.uuidString }.joined(separator: ",")
        let selectedSession = terminalSessionId?.uuidString ?? "nil"
        let sideKey = side == .left ? "left" : "right"
        return "\(worktree.objectID.uriRepresentation().absoluteString)|\(selectedSession)|\(sessionIds)|\(sideKey)"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .background(AppSurfaceTheme.backgroundColor())
        .transaction { transaction in
            if isResizing {
                transaction.disablesAnimations = true
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: panel.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(panel.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(panelSubtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button {
                onClose()
            } label: {
                Image(systemName: side == .left ? "chevron.left.circle.fill" : "chevron.right.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.thinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.5))
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch panel {
        case .terminal:
            AizenTerminalRootContainer(identity: terminalHostIdentity) {
                TerminalTabView(
                    worktree: worktree,
                    sessions: terminalSessions,
                    isVisible: true,
                    selectedSessionId: $terminalSessionId,
                    repositoryManager: repositoryManager
                )
            }

        case .files:
            FileTabView(
                worktree: worktree,
                fileToOpenFromSearch: $fileToOpen,
                showPathHeader: false,
                store: fileBrowserStore
            )

        case .browser:
            if let browserSessionStore {
                BrowserTabView(
                    manager: browserSessionStore,
                    selectedSessionId: $browserSessionId,
                    isSelected: true
                )
                .id(ObjectIdentifier(browserSessionStore))
            } else {
                BrowserTabView(
                    worktree: worktree,
                    selectedSessionId: $browserSessionId,
                    isSelected: true
                )
                .id(worktree.objectID)
            }

        case .gitDiff:
            CompanionGitDiffView(
                worktree: worktree,
                onSummaryChange: { summary in
                    if gitDiffSubtitle != summary {
                        gitDiffSubtitle = summary
                    }
                }
            )
        }
    }
}
