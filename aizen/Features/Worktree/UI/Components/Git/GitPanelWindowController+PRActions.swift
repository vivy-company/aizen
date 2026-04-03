//
//  GitPanelWindowController+PRActions.swift
//  aizen
//
//  PR/MR toolbar actions for the git panel window content.
//

import AppKit
import SwiftUI
import os

extension GitPanelWindowContentWithToolbar {
    var isOnMainBranch: Bool {
        let branch = gitStatus.currentBranch.lowercased()
        return branch == "main" || branch == "master"
    }

    @ViewBuilder
    var prActionButton: some View {
        if let info = hostingInfo, info.provider != .unknown, !isOnMainBranch {
            if prOperationInProgress {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(info.provider == .gitlab ? "MR..." : "PR...")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            } else {
                switch prStatus {
                case .unknown, .noPR:
                    Button {
                        createPR()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.pull")
                            Text(info.provider == .gitlab ? "Create MR" : "Create PR")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isOperationPending || gitStatus.currentBranch.isEmpty)

                case .open(let number, let url, let mergeable, let title):
                    HStack(spacing: 4) {
                        Button {
                            if let prURL = URL(string: url) {
                                NSWorkspace.shared.open(prURL)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "number")
                                Text("\(number)")
                            }
                        }
                        .buttonStyle(.bordered)
                        .help(title)

                        Button {
                            mergePR(number: number)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.triangle.merge")
                                Text("Merge")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(!mergeable || isOperationPending)
                        .help(mergeable ? "Merge this PR" : "PR cannot be merged (conflicts or checks failing)")
                    }

                case .merged, .closed:
                    Button {
                        createPR()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.pull")
                            Text(info.provider == .gitlab ? "Create MR" : "Create PR")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isOperationPending || gitStatus.currentBranch.isEmpty)
                }
            }
        }
    }

    func loadHostingInfo() async {
        guard let path = worktree.path else { return }
        hostingInfo = await gitHostingService.getHostingInfo(for: path)
        await refreshPRStatus()
    }

    func loadHostingInfoIfNeeded() {
        guard hostingInfo == nil, hostingInfoTask == nil else { return }
        hostingInfoTask = Task {
            await loadHostingInfo()
            await MainActor.run {
                hostingInfoTask = nil
            }
        }
    }

    func refreshPRStatus() async {
        guard let path = worktree.path,
              let info = hostingInfo,
              info.cliInstalled && info.cliAuthenticated else {
            prStatus = .unknown
            return
        }

        let branch = gitStatus.currentBranch
        guard !branch.isEmpty else {
            prStatus = .unknown
            return
        }

        prStatus = await gitHostingService.getPRStatus(repoPath: path, branch: branch)
    }

    func createPR() {
        guard let info = hostingInfo else { return }
        let branch = gitStatus.currentBranch
        guard !branch.isEmpty else { return }

        if !info.cliInstalled || !info.cliAuthenticated {
            if info.provider == .bitbucket || info.provider.cliName == nil {
                Task {
                    await gitHostingService.openInBrowser(
                        info: info,
                        action: .createPR(sourceBranch: branch, targetBranch: nil)
                    )
                }
            } else {
                showCLIInstallAlert = true
            }
            return
        }

        prOperationInProgress = true
        Task {
            do {
                guard let path = worktree.path else { return }
                try await gitHostingService.createPR(repoPath: path, sourceBranch: branch)
                await refreshPRStatus()
            } catch {
                logger.error("Failed to create PR: \(error.localizedDescription)")
                await gitHostingService.openInBrowser(
                    info: info,
                    action: .createPR(sourceBranch: branch, targetBranch: nil)
                )
            }
            prOperationInProgress = false
        }
    }

    func mergePR(number: Int) {
        guard let info = hostingInfo else { return }

        if !info.cliInstalled || !info.cliAuthenticated {
            if let url = gitHostingService.buildURL(info: info, action: .viewPR(number: number)) {
                NSWorkspace.shared.open(url)
            }
            return
        }

        prOperationInProgress = true
        Task {
            do {
                guard let path = worktree.path else { return }
                try await gitHostingService.mergePR(repoPath: path, prNumber: number)
                await refreshPRStatus()
                runtime.refreshSummary(lightweight: false)
            } catch {
                logger.error("Failed to merge PR: \(error.localizedDescription)")
            }
            prOperationInProgress = false
        }
    }
}
