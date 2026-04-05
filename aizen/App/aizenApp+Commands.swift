//
//  aizenApp+Commands.swift
//  aizen
//
//  Created by OpenAI Codex on 05.04.26.
//

import AppKit
import Sparkle
import SwiftUI

extension aizenApp {
    @CommandsBuilder
    var appCommands: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Aizen") {
                showAboutWindow()
            }
        }

        CommandGroup(after: .appInfo) {
            CheckForUpdatesView(updater: updaterController.updater)
        }

        CommandGroup(replacing: .appSettings) {
            Button {
                SettingsWindowController.shared.show()
            } label: {
                Label("Settings...", systemImage: "gearshape")
            }
            .keyboardShortcut(",", modifiers: .command)
        }

        CommandGroup(after: .appSettings) {
            Button {
                installCLIFromMenu()
            } label: {
                Label("Install CLI...", systemImage: "terminal")
            }
        }

        CommandGroup(after: .newItem) {
            Button("Activity Monitor...") {
                ActiveWorktreesWindowController.shared.show(context: persistenceController.container.viewContext)
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])

            Button("Chat Sessions...") {
                SessionsWindowController.shared.show(context: persistenceController.container.viewContext)
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])

            Divider()

            Button("Split Right") {
                TerminalSplitActionRouter.shared.splitHorizontal()
            }
            .keyboardShortcut("d", modifiers: .command)

            Button("Split Down") {
                TerminalSplitActionRouter.shared.splitVertical()
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])

            Button("Close Pane") {
                TerminalSplitActionRouter.shared.closePane()
            }
            .keyboardShortcut("w", modifiers: .command)

            Divider()

            Button("Cycle Mode") {
                chatActions?.cycleModeForward()
            }
        }

        CommandGroup(replacing: .help) {
            Button("Join Discord Community") {
                if let url = URL(string: "https://discord.gg/zemMZtrkSb") {
                    NSWorkspace.shared.open(url)
                }
            }

            Button("View on GitHub") {
                if let url = URL(string: "https://github.com/vivy-company/aizen") {
                    NSWorkspace.shared.open(url)
                }
            }

            Button("Report an Issue") {
                if let url = URL(string: "https://github.com/vivy-company/aizen/issues") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
}
