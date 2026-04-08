//
//  TerminalPaneView.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import AppKit
import GhosttyKit
import SwiftUI

// MARK: - Voice Action

enum VoiceAction: Hashable {
    case toggle
    case cancel
    case accept
}

// MARK: - Terminal Pane View

struct TerminalPaneView: View {
    @ObservedObject var worktree: Worktree
    @ObservedObject var session: TerminalSession
    let paneId: String
    let effectiveThemeName: String
    let isSplit: Bool
    let isFocused: Bool
    let sessionManager: TerminalRuntimeStore
    @Binding var voiceAction: VoiceAction?
    let focusRequestVersion: Int
    let onFocus: () -> Void
    let onProcessExit: () -> Void
    let onTitleChange: (String) -> Void
    let onVoiceRecordingChanged: (Bool) -> Void

    @EnvironmentObject var ghosttyApp: Ghostty.App

    @State var surfaceView: AizenTerminalSurfaceView?
    @StateObject var audioService = AudioService()
    @State var showingVoiceRecording = false
    @State var showingPermissionError = false
    @State var permissionErrorMessage = ""
    @ObservedObject private var terminalTitleRegistry = TerminalTitleRegistry.shared

    @AppStorage("terminalNotificationsEnabled") private var notificationsEnabled = true
    @AppStorage("terminalProgressEnabled") var progressEnabled = true
    @AppStorage("terminalVoiceButtonEnabled") var voiceButtonEnabled = true

    var surfaceAdapter: AizenTerminalSurfaceAdapter {
        AizenTerminalSurfaceAdapter(
            session: session,
            worktree: worktree,
            paneId: paneId,
            sessionManager: sessionManager,
            onProcessExit: {
                if notificationsEnabled && (!isFocused || !NSApp.isActive) {
                    TerminalNotificationCoordinator.shared.notify(
                        title: "Terminal exited",
                        body: terminalTitleRegistry.title(for: session) ?? "Shell process ended"
                    )
                }
                onProcessExit()
            },
            onFocus: onFocus,
            onReady: { },
            onTitleChange: onTitleChange,
            onProgress: { _, _ in }
        )
    }
}
