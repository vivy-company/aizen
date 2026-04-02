//
//  AppNavigationSelectionStore.swift
//  aizen
//
//  Created by Codex on 03.04.26.
//

import CoreData
import Combine

@MainActor
final class AppNavigationSelectionStore: ObservableObject {
    @Published var selectedWorkspace: Workspace?
    @Published var isCrossProjectSelected = false
    @Published var selectedRepository: Repository?
    @Published var selectedWorktree: Worktree?
    @Published var crossProjectWorktree: Worktree?
    @Published var zenModeBeforeCrossProjectSelection: Bool?
    @Published var suppressWorkspaceAutoSelection = false
}
