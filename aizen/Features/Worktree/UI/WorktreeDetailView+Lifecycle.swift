//
//  WorktreeDetailView+Lifecycle.swift
//  aizen
//
//  Shell modifiers and lifecycle wiring for the worktree detail screen
//

import SwiftUI

extension WorktreeDetailView {
    var detailSurfaceColor: Color {
        if selectedTab == "terminal", let cachedTerminalBackgroundColor {
            return cachedTerminalBackgroundColor
        }
        return AppSurfaceTheme.backgroundColor(colorScheme: colorScheme)
    }

    func getTerminalBackgroundColor() -> Color {
        AppSurfaceTheme.backgroundColor(colorScheme: colorScheme)
    }

    @ViewBuilder
    var contentWithBasicModifiers: some View {
        mainContentWithSidebars
            .navigationTitle(worktree.branch ?? String(localized: "worktree.session.worktree"))
            .background(detailSurfaceColor.ignoresSafeArea(.container, edges: .top))
            .toolbarBackground(Visibility.visible, for: .windowToolbar)
            .toast()
            .onAppear {
                cachedTerminalBackgroundColor = getTerminalBackgroundColor()
            }
            .task(id: colorScheme) {
                cachedTerminalBackgroundColor = getTerminalBackgroundColor()
            }
            .toolbar {
                leadingToolbarItems

                tabPickerToolbarItem

                sessionToolbarItems

                if #available(macOS 26.0, *) {
                    ToolbarSpacer()
                } else {
                    ToolbarItem(placement: .automatic) {
                        Spacer()
                    }
                }

                trailingToolbarItems
            }
            .background {
                Group {
                    Button("") { cycleVisibleTab(step: 1) }
                        .keyboardShortcut(.tab, modifiers: [.control])
                    Button("") { cycleVisibleTab(step: -1) }
                        .keyboardShortcut(.tab, modifiers: [.control, .shift])
                    Button("") { selectVisibleTab(at: 1) }
                        .keyboardShortcut("1", modifiers: .command)
                    Button("") { selectVisibleTab(at: 2) }
                        .keyboardShortcut("2", modifiers: .command)
                    Button("") { selectVisibleTab(at: 3) }
                        .keyboardShortcut("3", modifiers: .command)
                    Button("") { selectVisibleTab(at: 4) }
                        .keyboardShortcut("4", modifiers: .command)
                }
                .hidden()
            }
            .task(id: worktree.id) {
                hasLoadedTabState = false
                loadTabState()
                validateSelectedTab()
                hasLoadedTabState = true
                worktreeRuntime.attachDetail(showXcode: showXcodeBuild)
            }
    }

    @ViewBuilder
    var navigationContent: some View {
        contentWithBasicModifiers
            .task(id: selectedTab) {
                guard hasLoadedTabState else { return }
                saveTabState()
            }
            .task(id: viewModel.selectedChatSessionId) {
                guard let worktreeId = worktree.id else { return }
                tabStateManager.saveSessionId(viewModel.selectedChatSessionId, for: "chat", worktreeId: worktreeId)
            }
            .task(id: viewModel.selectedTerminalSessionId) {
                guard let worktreeId = worktree.id else { return }
                tabStateManager.saveSessionId(viewModel.selectedTerminalSessionId, for: "terminal", worktreeId: worktreeId)
            }
            .task(id: viewModel.selectedBrowserSessionId) {
                guard let worktreeId = worktree.id else { return }
                tabStateManager.saveSessionId(viewModel.selectedBrowserSessionId, for: "browser", worktreeId: worktreeId)
            }
            .task(id: viewModel.selectedFileSessionId) {
                guard let worktreeId = worktree.id else { return }
                tabStateManager.saveSessionId(viewModel.selectedFileSessionId, for: "files", worktreeId: worktreeId)
            }
            .onDisappear {
                worktreeRuntime.detachDetail()
            }
            .task(id: showXcodeBuild) {
                worktreeRuntime.updateDetailOptions(showXcode: showXcodeBuild)
            }
    }
}
