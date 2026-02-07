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
    let repositoryManager: RepositoryManager
    let side: CompanionSide
    let onClose: () -> Void
    let isResizing: Bool

    @Binding var terminalSessionId: UUID?
    @Binding var browserSessionId: UUID?
    @State private var fileToOpen: String?
    @State private var isHoveringClose = false
    @State private var gitDiffSubtitle: String = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: side == .left ? .trailing : .leading) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.55))
                .frame(width: 1)
                .allowsHitTesting(false)
        }
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
                    .foregroundStyle(isHoveringClose ? .primary : .secondary)
            }
            .buttonStyle(.plain)
            .help("Collapse panel")
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHoveringClose = hovering
                }
            }
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

    private var panelSubtitle: String {
        switch panel {
        case .terminal:
            return terminalSubtitle
        case .files:
            return worktreePathSubtitle
        case .browser:
            return browserSubtitle
        case .gitDiff:
            return gitDiffSubtitle.isEmpty ? worktreeNameFallback : gitDiffSubtitle
        }
    }

    private var terminalSubtitle: String {
        if let session = selectedTerminalSession ?? terminalSessions.last {
            if let title = session.title, !title.isEmpty {
                return title
            }
        }
        return worktreeNameFallback
    }

    private var browserSubtitle: String {
        if let session = selectedBrowserSession ?? browserSessions.last {
            if let title = session.title, !title.isEmpty {
                return title
            }
            if let url = session.url, !url.isEmpty {
                return url
            }
        }
        return worktreeNameFallback
    }

    private var worktreePathSubtitle: String {
        guard let path = worktree.path, !path.isEmpty else { return "No worktree path" }
        return path
    }

    private var worktreeNameFallback: String {
        guard let path = worktree.path, !path.isEmpty else { return "Worktree" }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    private var terminalSessions: [TerminalSession] {
        let sessions = (worktree.terminalSessions as? Set<TerminalSession>) ?? []
        return sessions
            .filter { !$0.isDeleted }
            .sorted { ($0.createdAt ?? Date()) < ($1.createdAt ?? Date()) }
    }

    private var selectedTerminalSession: TerminalSession? {
        guard let id = terminalSessionId else { return nil }
        return terminalSessions.first(where: { $0.id == id })
    }

    private var browserSessions: [BrowserSession] {
        let sessions = (worktree.browserSessions as? Set<BrowserSession>) ?? []
        return sessions
            .filter { !$0.isDeleted }
            .sorted { ($0.createdAt ?? Date()) < ($1.createdAt ?? Date()) }
    }

    private var selectedBrowserSession: BrowserSession? {
        guard let id = browserSessionId else { return nil }
        return browserSessions.first(where: { $0.id == id })
    }

    @ViewBuilder
    private var content: some View {
        switch panel {
        case .terminal:
            TerminalTabView(
                worktree: worktree,
                selectedSessionId: $terminalSessionId,
                repositoryManager: repositoryManager
            )

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
