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
    @AppStorage("terminalProgressEnabled") private var progressEnabled = true
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

    var body: some View {
        Group {
            if let surfaceView {
                AizenInspectableSurface(
                    surfaceView: surfaceView,
                    adapter: surfaceAdapter,
                    effectiveThemeName: effectiveThemeName,
                    isSplit: isSplit,
                    isFocused: isFocused,
                    showsProgress: progressEnabled
                )
                .overlay(alignment: .bottom) {
                    if showingVoiceRecording {
                        voiceOverlay
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if !showingVoiceRecording && isFocused && voiceButtonEnabled {
                        voiceTriggerButton
                            .transition(.opacity)
                    }
                }
            } else {
                Color.clear
                    .onAppear {
                        resolveSurfaceIfNeeded()
                    }
            }
        }
        .onAppear {
            resolveSurfaceIfNeeded()
            surfaceView?.setGhosttyFocused(isFocused)
            if isFocused {
                requestSurfaceFocus()
            }
        }
        .task(id: isFocused) {
            surfaceView?.setGhosttyFocused(isFocused)
            if isFocused {
                requestSurfaceFocus()
            }
            if !isFocused, showingVoiceRecording {
                audioService.cancelRecording()
                setVoiceRecording(false)
            }
        }
        .task(id: focusRequestVersion) {
            if isFocused {
                requestSurfaceFocus()
            }
        }
        .onDisappear {
            if showingVoiceRecording {
                audioService.cancelRecording()
                setVoiceRecording(false)
            }
        }
        .task(id: voiceAction) {
            guard let action = voiceAction else { return }
            handleVoiceAction(action)
            voiceAction = nil
        }
        .alert("Voice Input Unavailable", isPresented: $showingPermissionError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(permissionErrorMessage)
        }
    }

}
