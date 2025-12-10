//
//  TerminalViewWrapper.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import SwiftUI
import AppKit
import Combine
import os.log

// MARK: - Terminal View Coordinator

class TerminalViewCoordinator {
    let session: TerminalSession
    let onProcessExit: () -> Void
    private var exitCheckTimer: Timer?

    init(session: TerminalSession, onProcessExit: @escaping () -> Void) {
        self.session = session
        self.onProcessExit = onProcessExit
    }

    func startMonitoring(terminal: GhosttyTerminalView) {
        // Poll for process exit every 500ms
        exitCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self, weak terminal] _ in
            guard let self = self, let terminal = terminal else { return }

            if terminal.processExited {
                self.exitCheckTimer?.invalidate()
                self.exitCheckTimer = nil
                self.onProcessExit()
            }
        }
    }

    func stopMonitoring() {
        exitCheckTimer?.invalidate()
        exitCheckTimer = nil
    }

    deinit {
        stopMonitoring()
    }
}

// MARK: - Terminal View Wrapper

struct TerminalViewWrapper: NSViewRepresentable {
    @ObservedObject var worktree: Worktree
    @ObservedObject var session: TerminalSession
    let paneId: String
    let sessionManager: TerminalSessionManager
    let onProcessExit: () -> Void
    let onReady: () -> Void
    let onTitleChange: (String) -> Void
    let onProgress: (GhosttyProgressState, Int?) -> Void
    let shouldFocus: Bool  // Pass value directly to trigger updateNSView
    let isFocused: Bool    // Track if this pane should have focus
    let focusVersion: Int  // Version counter - forces updateNSView when changed
    let size: CGSize       // Frame size from GeometryReader

    @EnvironmentObject var ghosttyApp: Ghostty.App

    func makeCoordinator() -> TerminalViewCoordinator {
        TerminalViewCoordinator(session: session, onProcessExit: onProcessExit)
    }

    func makeNSView(context: Context) -> NSView {
        // Guard against deleted session
        guard let sessionId = session.id else {
            return NSView(frame: .zero)
        }

        // Check if terminal already exists for this pane
        if let existingTerminal = sessionManager.getTerminal(for: sessionId, paneId: paneId) {
            context.coordinator.startMonitoring(terminal: existingTerminal)

            DispatchQueue.main.async {
                existingTerminal.onProcessExit = onProcessExit
                existingTerminal.onProgressReport = onProgress
                existingTerminal.onTitleChange = onTitleChange
                existingTerminal.needsLayout = true
                existingTerminal.layoutSubtreeIfNeeded()
                onReady()
            }

            return existingTerminal
        }

        // Ensure Ghostty app is ready
        guard let app = ghosttyApp.app else {
            return NSView(frame: .zero)
        }

        // Get worktree path
        guard let path = worktree.path else {
            return NSView(frame: .zero)
        }

        // Create new Ghostty terminal
        // Apply initial command only for the first terminal created in a session
        // (subsequent splits shouldn't re-run the command)
        let isFirstTerminalInSession = sessionManager.getTerminalCount(for: sessionId) == 0
        let initialCommand = isFirstTerminalInSession ? session.initialCommand : nil
        Logger.terminal.info("makeNSView: session.id=\(session.id?.uuidString ?? "nil"), paneId=\(paneId), isFirst=\(isFirstTerminalInSession), initialCommand=\(initialCommand ?? "nil")")
        let terminalView = GhosttyTerminalView(
            frame: .zero,
            worktreePath: path,
            ghosttyApp: app,
            appWrapper: ghosttyApp,
            command: initialCommand
        )
        terminalView.onReady = onReady
        terminalView.onTitleChange = onTitleChange

        // Set process exit callback
        terminalView.onProcessExit = onProcessExit

        // Set title change callback to update session title
        let sessionToUpdate = session
        let worktreeToUpdate = worktree
        let moc = session.managedObjectContext
        terminalView.onProgressReport = onProgress

        // Store terminal in manager for persistence
        sessionManager.setTerminal(terminalView, for: sessionId, paneId: paneId)

        // Start monitoring for process exit
        context.coordinator.startMonitoring(terminal: terminalView)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            onReady()
        }

        return terminalView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Always update frame size to match allocated space
        // This matches Ghostty's SurfaceRepresentable approach
        if nsView.frame.size != size || nsView.frame.origin != .zero {
            nsView.frame = CGRect(origin: .zero, size: size)
            nsView.needsLayout = true
            nsView.layoutSubtreeIfNeeded()
        }

        // Handle focus changes
        if shouldFocus {
            guard let window = nsView.window else { return }
            window.makeFirstResponder(nsView)
        } else if !isFocused && nsView.window?.firstResponder == nsView {
            nsView.window?.makeFirstResponder(nil)
        }

        // Keep callbacks up to date if settings/state changed
        if let terminalView = nsView as? GhosttyTerminalView {
            terminalView.onProcessExit = onProcessExit
            terminalView.onProgressReport = onProgress
            terminalView.onTitleChange = onTitleChange
        }
    }
}
