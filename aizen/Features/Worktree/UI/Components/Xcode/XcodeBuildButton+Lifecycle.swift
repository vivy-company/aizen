//
//  XcodeBuildButton+Lifecycle.swift
//  aizen
//
//  Created by OpenAI Codex on 06.04.26.
//

import SwiftUI

extension XcodeBuildButton {
    var buttonBody: some View {
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
