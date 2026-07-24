//
//  aizenApp+Support.swift
//  aizen
//
//  Created by OpenAI Codex on 05.04.26.
//

import AppKit
import CoreData
import SwiftUI

extension aizenApp {
    func showAboutWindow() {
        if let existingWindow = aboutWindow, existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil as Any?)
            return
        }

        let aboutView = AboutView()
            .modifier(AppearanceModifier())
        let hostingController = NSHostingController(rootView: aboutView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "About Aizen"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)

        aboutWindow = window
    }

    func installCLIFromMenu() {
        let result = CLISymlinkService.install()
        let alert = NSAlert()
        alert.messageText = "CLI Installation"
        alert.informativeText = result.message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    /// Clean up orphaned tmux sessions that no longer have matching Core Data panes
    func cleanupOrphanedTmuxSessions() async {
        guard sessionPersistence else { return }

        let context = persistenceController.container.viewContext
        var validPaneIds = Set<String>()

        await context.perform {
            do {
                let layoutRequest: NSFetchRequest<WorktreeLayout> = WorktreeLayout.fetchRequest()
                for layout in try context.fetch(layoutRequest) {
                    if let treeJSON = layout.treeJSON,
                       let tree = WorkspaceLayoutCodec.decode(treeJSON) {
                        validPaneIds.formUnion(tree.allPaneIds())
                    }
                }

                // Terminal sessions of worktrees not yet migrated to workspace layouts.
                let sessionRequest: NSFetchRequest<TerminalSession> = TerminalSession.fetchRequest()
                for session in try context.fetch(sessionRequest) {
                    if let layoutJSON = session.splitLayout,
                       let layout = WorkspaceLayoutCodec.decode(layoutJSON) {
                        validPaneIds.formUnion(layout.allPaneIds())
                    }
                }
            } catch {
                // Best-effort cleanup only.
            }
        }

        await TmuxSessionRuntime.shared.cleanupOrphanedSessions(validPaneIds: validPaneIds)
    }
}
