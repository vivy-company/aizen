//
//  ZenModeCommands.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 24.11.25.
//

import SwiftUI

struct ZenModeCommands: Commands {
    @AppStorage("zenModeEnabled") private var zenModeEnabled = false

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button(zenModeEnabled ? "Exit Zen Mode" : "Enter Zen Mode") {
                zenModeEnabled.toggle()
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
        }
    }
}
