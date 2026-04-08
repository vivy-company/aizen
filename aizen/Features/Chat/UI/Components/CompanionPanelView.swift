//
//  CompanionPanelView.swift
//  aizen
//
//  Renders the active companion panel (terminal/files/browser)
//

import ACP
import SwiftUI

struct CompanionPanelView: View {
    let panel: CompanionPanel
    let worktree: Worktree
    let repositoryManager: WorkspaceRepositoryStore
    let side: CompanionSide
    let onClose: () -> Void
    let isResizing: Bool

    @Binding var terminalSessionId: UUID?
    @Binding var browserSessionId: UUID?
    @State private var fileToOpen: String?
    @State var gitDiffSubtitle: String = ""

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
            AizenTerminalRootContainer {
                TerminalTabView(
                    worktree: worktree,
                    selectedSessionId: $terminalSessionId,
                    repositoryManager: repositoryManager
                )
            }

        case .files:
            FileTabView(
                worktree: worktree,
                fileToOpenFromSearch: $fileToOpen,
                showPathHeader: false
            )

        case .browser:
            BrowserTabView(
                worktree: worktree,
                selectedSessionId: $browserSessionId
            )

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
