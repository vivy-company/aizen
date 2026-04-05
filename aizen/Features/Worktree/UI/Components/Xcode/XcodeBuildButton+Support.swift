//
//  XcodeBuildButton+Support.swift
//  aizen
//
//  Created by OpenAI Codex on 06.04.26.
//

import SwiftUI

extension XcodeBuildButton {
    @ViewBuilder
    var runButton: some View {
        Button {
            handleRunAction()
        } label: {
            buildStatusIcon
        }
        .labelStyle(.iconOnly)
        .disabled(buildManager.currentPhase.isBuilding && !canCancel)
        .help(buttonHelp)
    }

    var canCancel: Bool {
        buildManager.currentPhase.isBuilding
    }

    func handleRunAction() {
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
    var buildStatusIcon: some View {
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
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        buildManager.resetStatus()
                    }
                }

        case .failed:
            Label("Failed", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    var buttonHelp: String {
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
