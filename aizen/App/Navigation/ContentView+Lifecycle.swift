//
//  ContentView+Lifecycle.swift
//  aizen
//
//  Created by Codex on 2026-04-03.
//

import Foundation
import SwiftUI

extension ContentView {
    func withLifecycleHandlers<Content: View>(_ content: Content) -> some View {
        content
            .onAppear(perform: handleOnAppear)
            .task(id: zenModeEnabled, handleZenModeChange)
            .onReceive(NotificationCenter.default.publisher(for: .commandPaletteShortcut)) { _ in
                showCommandPalette()
            }
            .onReceive(NotificationCenter.default.publisher(for: .quickSwitchWorktree)) { _ in
                quickSwitchToPreviousWorktree()
            }
            .onReceive(NotificationCenter.default.publisher(for: .navigateToWorktree), perform: handleNavigateToWorktree)
            .onReceive(NotificationCenter.default.publisher(for: .navigateToChatSession), perform: handleNavigateToChatSession)
    }

    func handleOnAppear() {
        if selectionStore.isCrossProjectSelected && selectionStore.crossProjectWorktree == nil {
            setCrossProjectSelected(false)
        }

        if selectionStore.selectedWorkspace == nil {
            if let workspaceId = selectedWorkspaceId,
               let uuid = UUID(uuidString: workspaceId),
               let workspace = workspaceGraphQueryController.workspace(id: uuid) {
                selectWorkspace(workspace)
            } else {
                selectWorkspace(workspaceGraphQueryController.workspaces.first)
            }
        }

        if !hasShownOnboarding {
            showingOnboarding = true
            hasShownOnboarding = true
        }
    }

    func handleZenModeChange() {
        if selectionStore.isCrossProjectSelected && !zenModeEnabled {
            zenModeEnabled = true
        }
    }

    func handleNavigateToWorktree(_ notification: Notification) {
        guard let info = notification.userInfo,
              let workspaceId = info["workspaceId"] as? UUID,
              let repoId = info["repoId"] as? UUID,
              let worktreeId = info["worktreeId"] as? UUID else {
            return
        }
        navigateToWorktree(workspaceId: workspaceId, repoId: repoId, worktreeId: worktreeId)
    }

    func handleNavigateToChatSession(_ notification: Notification) {
        guard let chatSessionId = notification.userInfo?["chatSessionId"] as? UUID else {
            return
        }
        navigator.navigateToChatSession(
            chatSessionId: chatSessionId,
            workspaceGraphQueryController: workspaceGraphQueryController,
            selectionStore: selectionStore,
            navigateToWorktree: navigateToWorktree
        )
    }
}
