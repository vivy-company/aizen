//
//  XcodeBuildButton.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 10.12.25.
//

import SwiftUI

struct XcodeBuildButton: View {
    @ObservedObject var buildManager: XcodeBuildStore
    let worktree: Worktree?

    @State var showingLogPopover = false
    @State var showingDebugLogs = false

    init(buildManager: XcodeBuildStore, worktree: Worktree? = nil) {
        self.buildManager = buildManager
        self.worktree = worktree
    }

    var body: some View {
        buttonBody
    }
}

#Preview {
    XcodeBuildButton(buildManager: XcodeBuildStore())
        .padding()
}
