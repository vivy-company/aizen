//
//  WorktreeDetailView+Toolbar.swift
//  aizen
//

import SwiftUI

extension WorktreeDetailView {
    @ToolbarContentBuilder
    var workspaceTabsToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            WorkspaceTabStripView(workspace: scene.workspace)
        }
    }

    @ToolbarContentBuilder
    var leadingToolbarItems: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            if showZenModeButton {
                HStack(spacing: 12) {
                    zenModeButton
                }
            }
        }
    }

    @ViewBuilder
    var zenModeButton: some View {
        let button = Button(action: {
            withAnimation(.easeInOut(duration: 0.25)) {
                zenModeEnabled.toggle()
            }
        }) {
            Label("Zen Mode", systemImage: zenModeEnabled ? "pip.enter" : "pip.exit")
        }
        .labelStyle(.iconOnly)
        .help(zenModeEnabled ? "Show Environment List" : "Hide Environment List (Zen Mode)")

        if #available(macOS 14.0, *) {
            button.symbolEffect(.bounce, value: zenModeEnabled)
        } else {
            button
        }
    }

    @ToolbarContentBuilder
    var trailingToolbarItems: some ToolbarContent {
        ToolbarItem {
            if showXcodeBuild, xcodeBuildManager.isReady {
                XcodeBuildButton(buildManager: xcodeBuildManager, worktree: worktree)
            }
        }

        if #available(macOS 26.0, *) {
            ToolbarSpacer(.fixed)
        } else {
            ToolbarItem(placement: .automatic) {
                Spacer().frame(width: 12).fixedSize()
            }
        }

        ToolbarItem {
            if showOpenInApp {
                OpenInAppButton(
                    lastOpenedApp: lastOpenedApp,
                    appDetector: appDetector,
                    onOpenInLastApp: openInLastApp,
                    onOpenInDetectedApp: openInDetectedApp
                )
            }
        }

        if #available(macOS 26.0, *) {
            ToolbarSpacer(.fixed)
        } else {
            ToolbarItem(placement: .automatic) {
                Spacer().frame(width: 12).fixedSize()
            }
        }

        ToolbarItem(placement: .automatic) {
            if showGitStatus && hasGitChanges {
                gitStatusView
            }
        }

        ToolbarItem(placement: .automatic) {
            gitSidebarButton
        }
    }
}
