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
            let request: NSFetchRequest<TerminalSession> = TerminalSession.fetchRequest()
            do {
                let sessions = try context.fetch(request)
                for session in sessions {
                    if let layoutJSON = session.splitLayout,
                       let layout = SplitLayoutHelper.decode(layoutJSON) {
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
