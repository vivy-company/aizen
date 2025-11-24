//
//  TerminalPaneView.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import SwiftUI

// MARK: - Terminal Pane View

struct TerminalPaneView: View {
    @ObservedObject var worktree: Worktree
    @ObservedObject var session: TerminalSession
    let paneId: String
    let isFocused: Bool
    let sessionManager: TerminalSessionManager
    let onFocus: () -> Void
    let onProcessExit: () -> Void

    @State private var shouldFocus: Bool = false
    @State private var focusVersion: Int = 0  // Increment to force updateNSView
    @State private var terminalView: GhosttyTerminalView?  // Store reference to resign directly

    var body: some View {
        GeometryReader { geo in
            TerminalViewWrapper(
                worktree: worktree,
                session: session,
                paneId: paneId,
                sessionManager: sessionManager,
                onProcessExit: onProcessExit,
                shouldFocus: shouldFocus,  // Pass value directly, not binding
                isFocused: isFocused,      // Pass focused state to manage resignation
                focusVersion: focusVersion, // Version counter to force updateNSView
                size: geo.size
            )
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .opacity(isFocused ? 1.0 : 0.6)
        .clipped()
        .onTapGesture {
            onFocus()
        }
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
    }
}
