import AppKit
import Foundation
import os.log

@MainActor
extension PullRequestsViewModel {
    func checkoutBranch() async {
        guard let pr = selectedPR else { return }

        isPerformingAction = true
        actionError = nil
        var primaryError: Error?

        if let provider = hostingInfo?.provider, provider == .github || provider == .gitlab {
            do {
                try await hostingService.checkoutPullRequest(repoPath: repoPath, number: pr.number)
                isPerformingAction = false
                return
            } catch {
                primaryError = error
                logger.error("PR checkout via CLI failed: \(error.localizedDescription)")
            }
        }

        do {
            try await checkoutBranchWithGit(pr.sourceBranch)
        } catch {
            logger.error("Failed to checkout branch: \(error.localizedDescription)")
            if let primaryError {
                actionError = "\(primaryError.localizedDescription)\n\(error.localizedDescription)"
            } else {
                actionError = error.localizedDescription
            }
        }

        isPerformingAction = false
    }

    func checkoutBranchWithGit(_ branch: String) async throws {
        let result = try await ProcessExecutor.shared.executeWithOutput(
            executable: "/usr/bin/git",
            arguments: ["checkout", branch],
            workingDirectory: repoPath
        )

        if result.exitCode != 0 {
            _ = try await ProcessExecutor.shared.executeWithOutput(
                executable: "/usr/bin/git",
                arguments: ["fetch", "origin", branch],
                workingDirectory: repoPath
            )

            let retryResult = try await ProcessExecutor.shared.executeWithOutput(
                executable: "/usr/bin/git",
                arguments: ["checkout", branch],
                workingDirectory: repoPath
            )

            if retryResult.exitCode != 0 {
                let trackResult = try await ProcessExecutor.shared.executeWithOutput(
                    executable: "/usr/bin/git",
                    arguments: ["checkout", "-b", branch, "origin/\(branch)"],
                    workingDirectory: repoPath
                )

                if trackResult.exitCode != 0 {
                    throw GitHostingError.commandFailed(message: trackResult.stderr)
                }
            }
        }
    }

    func openInBrowser() {
        guard let pr = selectedPR, let url = URL(string: pr.url) else { return }
        NSWorkspace.shared.open(url)
    }
}
