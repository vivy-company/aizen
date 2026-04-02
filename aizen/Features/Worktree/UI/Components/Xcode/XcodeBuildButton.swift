//
//  XcodeBuildButton.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 10.12.25.
//

import SwiftUI

struct XcodeBuildButton: View {
    @ObservedObject var buildManager: XcodeBuildManager
    let worktree: Worktree?

    @State private var showingLogPopover = false
    @State private var showingDebugLogs = false

    init(buildManager: XcodeBuildManager, worktree: Worktree? = nil) {
        self.buildManager = buildManager
        self.worktree = worktree
    }

    var body: some View {
        HStack(spacing: 0) {
            runButton

            // Debug logs button (shown when app has been launched and is running)
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

    @ViewBuilder
    private var runButton: some View {
        Button {
            handleRunAction()
        } label: {
            buildStatusIcon
        }
        .labelStyle(.iconOnly)
        .disabled(buildManager.currentPhase.isBuilding && !canCancel)
        .help(buttonHelp)
    }

    private var canCancel: Bool {
        buildManager.currentPhase.isBuilding
    }

    private func handleRunAction() {
        switch buildManager.currentPhase {
        case .idle:
            buildManager.buildAndRun()
        case .building, .launching:
            buildManager.cancelBuild()
        case .succeeded:
            buildManager.resetStatus()
            buildManager.buildAndRun()
        case .failed:
            showingLogPopover = true
        }
    }

    @ViewBuilder
    private var buildStatusIcon: some View {
        switch buildManager.currentPhase {
        case .idle:
            Label("Run", systemImage: "play.fill")

        case .building(let progress):
            ProgressView()
                .controlSize(.small)
                .help(progress ?? "Building...")

        case .launching:
            ProgressView()
                .controlSize(.small)
                .help("Launching...")

        case .succeeded:
            Label("Succeeded", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .onAppear {
                    // Reset to idle after 2 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        buildManager.resetStatus()
                    }
                }

        case .failed:
            Label("Failed", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    private var buttonHelp: String {
        switch buildManager.currentPhase {
        case .idle:
            if let scheme = buildManager.selectedScheme,
               let dest = buildManager.selectedDestination {
                return "Build \(scheme) for \(dest.name)"
            }
            return "Build and Run"
        case .building:
            return "Cancel Build"
        case .launching:
            return "Launching..."
        case .succeeded:
            return "Build Succeeded - Click to run again"
        case .failed(let error, _):
            return "Build Failed: \(error) - Click for details"
        }
    }
}

#Preview {
    XcodeBuildButton(buildManager: XcodeBuildManager())
        .padding()
}
