//
//  WorktreeDetailView+Toolbar.swift
//  aizen
//

import SwiftUI

struct WorktreeTabPicker: View {
    @ObservedObject var scene: WorktreeSceneStore
    let visibleTabs: [TabItem]

    var body: some View {
        let selection = Binding(
            get: { scene.selectedTab },
            set: { newValue in
                guard scene.selectedTab != newValue else { return }
                DispatchQueue.main.async {
                    scene.selectTab(newValue)
                }
            }
        )
        return Picker(String(localized: "worktree.session.tab"), selection: selection) {
            ForEach(visibleTabs) { tab in
                Label(LocalizedStringKey(tab.localizedKey), systemImage: tab.icon)
                    .tag(tab.id)
            }
        }
        .pickerStyle(.segmented)
    }
}

extension WorktreeDetailView {
    @ToolbarContentBuilder
    var tabPickerToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            WorktreeTabPicker(scene: scene, visibleTabs: visibleTabs)
        }
    }

    var visibleTabs: [TabItem] {
        tabConfig.tabOrder.filter { isTabVisible($0.id) }
    }

    @ToolbarContentBuilder
    var sessionToolbarItems: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            if shouldShowSessionToolbar {
                SessionTabsScrollView(
                    selectedTab: selectedTab,
                    chatSessions: sessionManager.chatSessions,
                    terminalSessions: sessionManager.terminalSessions,
                    selectedChatSessionId: $viewModel.selectedChatSessionId,
                    selectedTerminalSessionId: $viewModel.selectedTerminalSessionId,
                    onCloseChatSession: sessionManager.closeChatSession,
                    onCloseTerminalSession: sessionManager.closeTerminalSession,
                    onCreateChatSession: sessionManager.createNewChatSession,
                    onCreateTerminalSession: sessionManager.createNewTerminalSession,
                    onCreateChatWithAgent: { agentId in
                        sessionManager.createNewChatSession(withAgent: agentId)
                    },
                    onCreateTerminalWithPreset: { preset in
                        sessionManager.createNewTerminalSession(withPreset: preset)
                    }
                )
            }
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
