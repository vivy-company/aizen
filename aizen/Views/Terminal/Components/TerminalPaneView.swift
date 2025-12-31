//
//  TerminalPaneView.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import SwiftUI
import AppKit

// MARK: - Terminal Pane View

struct TerminalPaneView: View {
    @ObservedObject var worktree: Worktree
    @ObservedObject var session: TerminalSession
    let paneId: String
    let isFocused: Bool
    let sessionManager: TerminalSessionManager
    let onFocus: () -> Void
    let onProcessExit: () -> Void
    let onTitleChange: (String) -> Void

    @State private var shouldFocus: Bool = false
    @State private var focusVersion: Int = 0  // Increment to force updateNSView
    @State private var isLoading: Bool = false
    @State private var progressState: GhosttyProgressState = .remove
    @State private var progressValue: Int? = nil
    @State private var isResizing: Bool = false
    @State private var terminalColumns: UInt16 = 0
    @State private var terminalRows: UInt16 = 0
    @State private var hideWorkItem: DispatchWorkItem?

    @AppStorage("terminalNotificationsEnabled") private var notificationsEnabled = true
    @AppStorage("terminalProgressEnabled") private var progressEnabled = true

    var body: some View {
        GeometryReader { geo in
            ZStack {
                TerminalViewWrapper(
                    worktree: worktree,
                    session: session,
                    paneId: paneId,
                    sessionManager: sessionManager,
                    onProcessExit: {
                        if notificationsEnabled && (!isFocused || !NSApp.isActive) {
                            TerminalNotificationManager.shared.notify(
                                title: "Terminal exited",
                                body: session.title ?? "Shell process ended"
                            )
                        }
                        onProcessExit()
                    },
                    onReady: { },
                    onTitleChange: onTitleChange,
                    onProgress: { state, value in
                        progressState = state
                        progressValue = value
                        if state == .remove {
                            isLoading = false
                        }
                    },
                    shouldFocus: shouldFocus,  // Pass value directly, not binding
                    isFocused: isFocused,      // Pass focused state to manage resignation
                    focusVersion: focusVersion, // Version counter to force updateNSView
                    size: geo.size
                )

                if progressEnabled && progressState != .remove && progressState != .unknown {
                    progressOverlay
                        .transition(.opacity)
                        .padding(.horizontal, 0)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }

                if isResizing {
                    ResizeOverlay(columns: terminalColumns, rows: terminalRows)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                        .animation(.easeOut(duration: 0.1), value: isResizing)
                }
            }
            .onChange(of: geo.size) { _ in
                handleSizeChange()
            }
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .opacity(isFocused ? 1.0 : 0.6)
        .clipped()
        .animation(nil, value: isFocused)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isFocused {
                        onFocus()
                    }
                }
        )
        .onChange(of: isFocused) { newValue in
            if newValue {
                shouldFocus = true
                focusVersion += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    shouldFocus = false
                }
            } else {
                focusVersion += 1
            }
        }
        .onAppear {
            if isFocused {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    shouldFocus = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        shouldFocus = false
                    }
                }
            }
        }
        .onDisappear {
            hideWorkItem?.cancel()
            hideWorkItem = nil
        }
    }

    private func handleSizeChange() {
        guard let sessionId = session.id,
              let terminal = sessionManager.getTerminal(for: sessionId, paneId: paneId),
              let termSize = terminal.terminalSize() else { return }

        terminalColumns = termSize.columns
        terminalRows = termSize.rows

        isResizing = true

        hideWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            isResizing = false
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }

    private var progressOverlay: some View {
        ZStack(alignment: .topLeading) {
            // Background track
            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(height: 2)
            // Determinate bar
            if progressState == .set, let value = progressValue {
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: geo.size.width * CGFloat(value) / 100.0, height: 2)
                        .animation(.easeOut(duration: 0.12), value: value)
                }
                .frame(height: 2)
            } else if progressState == .indeterminate || progressState == .pause || progressState == .error {
                // Indeterminate "ping-pong" bar
                IndeterminateBar(color: progressState == .error ? .red : .accentColor)
                    .frame(height: 2)
            }
        }
        .padding(.horizontal, 0.5)
    }
}
