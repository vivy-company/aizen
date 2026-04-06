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
