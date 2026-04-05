//
//  ActiveTabIndicatorView.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 19.11.25.
//

import ACP
import SwiftUI

struct ActiveTabIndicatorView: View {
    let worktree: Worktree
    @ObservedObject var tabStateManager: WorktreeTabStateStore
    @Environment(\.managedObjectContext) var viewContext
    @ObservedObject var terminalTitleRegistry = TerminalTitleRegistry.shared

    var body: some View {
        if let info = activeTabInfo {
            HStack(spacing: 4) {
                Image(systemName: info.icon)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                Text(info.title)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }
}
