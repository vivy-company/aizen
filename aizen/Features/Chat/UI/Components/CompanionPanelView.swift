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
    @State var fileToOpen: String?
    @State var gitDiffSubtitle: String = ""
}
