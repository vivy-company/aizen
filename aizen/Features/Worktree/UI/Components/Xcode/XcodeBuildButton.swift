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
    @State private var showingDebugLogs = false

    init(buildManager: XcodeBuildStore, worktree: Worktree? = nil) {
        self.buildManager = buildManager
        self.worktree = worktree
    }

    var body: some View {
        HStack(spacing: 0) {
            runButton

            if buildManager.launchedBundleId != nil {
                Divider()
                    .frame(height: 16)

                Button {
                    showingDebugLogs = true
                } label: {
                    Label("Logs", systemImage: "apple.terminal")
                }
                .labelStyle(.iconOnly)
                .help("View Debug Logs")
            }

            Divider()
                .frame(height: 16)

            XcodeDestinationPicker(buildManager: buildManager)
        }
        .popover(isPresented: $showingLogPopover) {
            XcodeBuildLogPopover(
                log: buildManager.lastBuildLog ?? "",
                duration: buildManager.lastBuildDuration,
                worktree: worktree,
                onRetry: {
                    buildManager.resetStatus()
                    buildManager.buildAndRun()
                },
                onDismiss: {
                    showingLogPopover = false
                }
            )
        }
        .sheet(isPresented: $showingDebugLogs) {
            XcodeLogSheetView(buildManager: buildManager)
        }
    }
}

#Preview {
    XcodeBuildButton(buildManager: XcodeBuildStore())
        .padding()
}
