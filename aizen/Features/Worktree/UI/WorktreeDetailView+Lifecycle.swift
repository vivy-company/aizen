//
//  WorktreeDetailView+Lifecycle.swift
//  aizen
//
//  Shell modifiers and lifecycle wiring for the worktree detail screen
//

import SwiftUI

extension WorktreeDetailView {
    var presentationSignature: String {
        "\(isActive)|\(showXcodeBuild)"
    }

    var detailSurfaceColor: Color {
        AppSurfaceTheme.backgroundColor(colorScheme: colorScheme)
    }

    @ViewBuilder
    var contentWithBasicModifiers: some View {
        mainContentWithSidebars
            .navigationTitle(worktree.branch ?? String(localized: "worktree.session.worktree"))
            .background(detailSurfaceColor.ignoresSafeArea(.container, edges: .top))
            .toolbarBackground(Visibility.visible, for: .windowToolbar)
            .toast()
            .toolbar {
                leadingToolbarItems

                workspaceTabsToolbarItem

                if #available(macOS 26.0, *) {
                    ToolbarSpacer()
                } else {
                    ToolbarItem(placement: .automatic) {
                        Spacer()
                    }
                }

                trailingToolbarItems
            }
            .task(id: presentationSignature) {
                scene.updatePresentation(
                    isActive: isActive,
                    showXcode: showXcodeBuild
                )
            }
    }

    @ViewBuilder
    var navigationContent: some View {
        contentWithBasicModifiers
            .onDisappear {
                scene.updatePresentation(
                    isActive: false,
                    showXcode: false
                )
            }
    }
}
