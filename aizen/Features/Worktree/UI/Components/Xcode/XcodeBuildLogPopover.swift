//
//  XcodeBuildLogPopover.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 10.12.25.
//

import SwiftUI
import AppKit

struct XcodeBuildLogPopover: View {
    let log: String
    let duration: TimeInterval?
    let worktree: Worktree?
    let onRetry: (() -> Void)?
    let onDismiss: (() -> Void)?
    let lines: [String]

    @State var showingSendToAgent = false
    @State var showCopiedFeedback = false
    @State var showFullLog = false

    init(
        log: String,
        duration: TimeInterval?,
        worktree: Worktree? = nil,
        onRetry: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.log = log
        self.duration = duration
        self.worktree = worktree
        self.onRetry = onRetry
        self.onDismiss = onDismiss
        self.lines = log.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    var body: some View {
        popoverContent
    }
}

#Preview {
    XcodeBuildLogPopover(
        log: """
        /path/to/File.swift:123:45: error: Cannot find 'foo' in scope
            let x = foo
                    ^~~
        /path/to/Other.swift:50:10: warning: Unused variable 'bar'
            let bar = 123
                ^~~
        ** BUILD FAILED **
        """,
        duration: 12.5,
        worktree: nil,
        onRetry: { print("Retry tapped") },
        onDismiss: { print("Dismiss tapped") }
    )
}
