//
//  SplitTerminalView.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import SwiftUI

struct SplitTerminalView: View {
    @ObservedObject var worktree: Worktree
    @ObservedObject var session: TerminalSession
    let sessionManager: TerminalRuntimeStore
    let isSelected: Bool

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppearanceSettings.themeNameKey) private var terminalThemeName = AppearanceSettings.defaultDarkTheme
    @AppStorage(AppearanceSettings.lightThemeNameKey) private var terminalThemeNameLight = AppearanceSettings.defaultLightTheme
    @AppStorage(AppearanceSettings.usePerAppearanceThemeKey) private var usePerAppearanceTheme = false

    @StateObject private var controller: TerminalSplitController
    private var effectiveThemeName: String {
        guard usePerAppearanceTheme else { return terminalThemeName }
        return AppearanceSettings.effectiveThemeName(colorScheme: colorScheme)
    }

    init(
        worktree: Worktree,
        session: TerminalSession,
        sessionManager: TerminalRuntimeStore,
        isSelected: Bool = false
    ) {
        self.worktree = worktree
        self.session = session
        self.sessionManager = sessionManager
        self.isSelected = isSelected
        _controller = StateObject(
            wrappedValue: TerminalSplitController(
                worktree: worktree,
                session: session,
                sessionManager: sessionManager,
                isSelected: isSelected
            )
        )
    }

    var body: some View {
        SplitTerminalSubtreeView(
            node: controller.layout,
            worktree: worktree,
            session: session,
            sessionManager: sessionManager,
            effectiveThemeName: effectiveThemeName,
            isSplit: false,
            focusedPaneId: controller.focusedPaneId,
            voiceAction: $controller.voiceAction,
            focusRequestVersion: controller.focusRequestVersion,
            onFocus: { controller.handlePaneFocus($0) },
            onProcessExit: { controller.handleProcessExit(for: $0) },
            onTitleChange: { controller.handleTitleChange(for: $0, title: $1) },
            onVoiceRecordingChanged: { controller.handleVoiceRecordingChanged(for: $0, isRecording: $1) },
            onResizeSplit: { controller.resizeSplit($0, to: $1) },
            onEqualize: { controller.equalize() }
        )
        .id(controller.layout.structuralIdentity)
        .onAppear {
            controller.handleAppear()
        }
        .task(id: isSelected) {
            controller.handleSelectionChange(isSelected)
        }
        .onDisappear {
            controller.handleDisappear()
        }
        .alert(
            String(localized: "terminal.close.confirmTitle", defaultValue: "Close Terminal?"),
            isPresented: $controller.showCloseConfirmation
        ) {
            Button(String(localized: "terminal.close.cancel", defaultValue: "Cancel"), role: .cancel) {}
            Button(String(localized: "terminal.close.confirm", defaultValue: "Close"), role: .destructive) {
                controller.executeCloseAction()
            }
            .keyboardShortcut(.defaultAction)
        } message: {
            Text(String(localized: "terminal.close.confirmMessage", defaultValue: "A process is still running in this terminal. Are you sure you want to close it?"))
        }
    }
}
