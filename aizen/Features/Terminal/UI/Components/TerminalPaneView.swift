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

private struct AizenInspectableSurface: View {
    @ObservedObject var surfaceView: AizenTerminalSurfaceView
    let adapter: AizenTerminalSurfaceAdapter
    let effectiveThemeName: String
    let isSplit: Bool
    let isFocused: Bool
    let showsProgress: Bool

    @FocusState private var surfaceFocus: Bool
    @State private var isHoveringURLLeft = false

    private var isFocusedSurface: Bool {
        surfaceFocus || isFocused
    }

    private var backgroundColor: Color {
        Color(nsColor: GhosttyThemeParser.loadBackgroundColor(named: effectiveThemeName))
    }

    var body: some View {
        ZStack {
            GeometryReader { geo in
                AizenTerminalSurfaceHost(
                    surfaceView: surfaceView,
                    adapter: adapter,
                    size: geo.size
                )
                .focused($surfaceFocus)

                if let surfaceSize = surfaceView.surfaceSize {
                    AizenSurfaceResizeOverlay(
                        geoSize: geo.size,
                        size: surfaceSize,
                        focusInstant: surfaceView.focusInstant
                    )
                }
            }

            if showsProgress,
               let progressReport = surfaceView.progressReport,
               progressReport.state != .remove {
                VStack(spacing: 0) {
                    AizenSurfaceProgressBar(report: progressReport)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(false)
                .transition(.opacity)
            }

            if let url = surfaceView.hoverUrl {
                let padding: CGFloat = 5
                let cornerRadius: CGFloat = 9
                ZStack {
                    HStack {
                        Spacer()
                        VStack(alignment: .leading) {
                            Spacer()

                            Text(verbatim: url)
                                .padding(.init(top: padding, leading: padding, bottom: padding, trailing: padding))
                                .background(
                                    UnevenRoundedRectangle(cornerRadii: .init(topLeading: cornerRadius))
                                        .fill(.background)
                                )
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .opacity(isHoveringURLLeft ? 1 : 0)
                        }
                    }

                    HStack {
                        VStack(alignment: .leading) {
                            Spacer()

                            Text(verbatim: url)
                                .padding(.init(top: padding, leading: padding, bottom: padding, trailing: padding))
                                .background(
                                    UnevenRoundedRectangle(cornerRadii: .init(topTrailing: cornerRadius))
                                        .fill(.background)
                                )
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .opacity(isHoveringURLLeft ? 0 : 1)
                                .onHover { hovering in
                                    isHoveringURLLeft = hovering
                                }
                        }
                        Spacer()
                    }
                }
            }

            if let searchState = surfaceView.searchState {
                AizenSurfaceSearchOverlay(
                    surfaceView: surfaceView,
                    searchState: searchState,
                    onClose: {
                        Ghostty.moveFocus(to: surfaceView)
                        surfaceView.searchState = nil
                    }
                )
            }

            AizenBellBorderOverlay(bell: surfaceView.bell)
            AizenHighlightOverlay(highlighted: surfaceView.highlighted)

            if !surfaceView.healthy {
                Rectangle().fill(backgroundColor)
                AizenSurfaceMessageView(
                    title: "Renderer Failed",
                    message: "The terminal renderer exhausted GPU resources or failed to recover."
                )
            } else if surfaceView.error != nil {
                Rectangle().fill(backgroundColor)
                AizenSurfaceMessageView(
                    title: "Terminal Failed",
                    message: "The terminal failed to initialize. Check logs for the underlying error."
                )
            }

            if isSplit && !isFocusedSurface {
                Rectangle()
                    .fill(backgroundColor)
                    .allowsHitTesting(false)
                    .opacity(0.28)
            }
        }
    }
}
