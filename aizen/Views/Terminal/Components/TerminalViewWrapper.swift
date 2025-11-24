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
                existingTerminal.needsLayout = true
                existingTerminal.layoutSubtreeIfNeeded()
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
        let terminalView = GhosttyTerminalView(
            frame: .zero,
            worktreePath: path,
            ghosttyApp: app,
            appWrapper: ghosttyApp
        )

        // Set process exit callback
        terminalView.onProcessExit = onProcessExit

        // Set title change callback to update session title
        let sessionToUpdate = session
        let worktreeToUpdate = worktree
        let moc = session.managedObjectContext
        terminalView.onTitleChange = { title in
            Task { @MainActor in
                sessionToUpdate.title = title

                // Notify observers explicitly
                sessionToUpdate.objectWillChange.send()
                worktreeToUpdate.objectWillChange.send()

                do {
                    try moc?.save()
                } catch {
                    Logger.terminal.error("Failed to save terminal title change: \(error.localizedDescription)")
                }
            }
        }

        // Store terminal in manager for persistence
        sessionManager.setTerminal(terminalView, for: sessionId, paneId: paneId)

        // Start monitoring for process exit
        context.coordinator.startMonitoring(terminal: terminalView)

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
    }
}
