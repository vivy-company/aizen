//
//  WorktreeDetailView+Lifecycle.swift
//  aizen
//
//  Shell modifiers and lifecycle wiring for the worktree detail screen
//

import SwiftUI

extension WorktreeDetailView {
    var presentationSignature: String {
        let visibleTabs = visibleTabIds.joined(separator: ",")
        return "\(isActive)|\(showXcodeBuild)|\(visibleTabs)"
    }

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
                loadTabState()
                validateSelectedTab()
            }
            .task(id: presentationSignature) {
                scene.updatePresentation(
                    isActive: isActive,
                    visibleTabIds: visibleTabIds,
                    showXcode: showXcodeBuild
                )
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
                guard hasLoadedTabState else { return }
                scene.saveSessionId(viewModel.selectedChatSessionId, for: "chat")
            }
            .task(id: viewModel.selectedTerminalSessionId) {
                guard hasLoadedTabState else { return }
                scene.saveSessionId(viewModel.selectedTerminalSessionId, for: "terminal")
            }
            .task(id: viewModel.selectedBrowserSessionId) {
                guard hasLoadedTabState else { return }
                scene.saveSessionId(viewModel.selectedBrowserSessionId, for: "browser")
            }
            .task(id: viewModel.selectedFileSessionId) {
                guard hasLoadedTabState else { return }
                scene.saveSessionId(viewModel.selectedFileSessionId, for: "files")
            }
            .onDisappear {
                scene.updatePresentation(
                    isActive: false,
                    visibleTabIds: [],
                    showXcode: false
                )
            }
    }
}
