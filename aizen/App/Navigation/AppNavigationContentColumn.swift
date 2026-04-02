//
//  AppNavigationContentColumn.swift
//  aizen
//
//  Created by Codex on 2026-04-03.
//

import SwiftUI

struct AppNavigationContentColumn: View {
    let isCrossProjectSelected: Bool
    let repository: Repository?
    @Binding var selectedWorktree: Worktree?
    let repositoryManager: RepositoryManager
    let tabStateManager: WorktreeTabStateStore
    let zenModeEnabled: Bool

    var body: some View {
        Group {
            if isCrossProjectSelected {
                Color.clear
            } else if let repository {
                WorktreeListView(
                    repository: repository,
                    selectedWorktree: $selectedWorktree,
                    repositoryManager: repositoryManager,
                    tabStateManager: tabStateManager
                )
            } else {
                placeholderView(
                    titleKey: "contentView.selectRepository",
                    systemImage: "folder.badge.gearshape",
                    descriptionKey: "contentView.selectRepositoryDescription"
                )
            }
        }
        .navigationSplitViewColumnWidth(
            min: zenModeEnabled ? 0 : 250,
            ideal: zenModeEnabled ? 0 : 300,
            max: zenModeEnabled ? 0 : 400
        )
        .opacity(zenModeEnabled ? 0 : 1)
        .allowsHitTesting(!zenModeEnabled)
        .animation(.easeInOut(duration: 0.25), value: zenModeEnabled)
    }
}
