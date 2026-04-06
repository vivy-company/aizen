//
//  WorktreeGitOperations+Commit.swift
//  aizen
//

import SwiftUI
import os.log

@MainActor
extension WorktreeGitOperations {
    func commit(_ message: String) {
        ToastStore.shared.showLoading("Committing changes...")
        gitOperationService.commit(
            message: message,
            onSuccess: {
                ToastStore.shared.show("Changes committed", type: .success)
            },
            onError: { [logger] error in
                ToastStore.shared.show("Commit failed: \(error.localizedDescription)", type: .error, duration: 5.0)
                logger.error("Failed to commit changes: \(error)")
            }
        )
    }

    func amendCommit(_ message: String) {
        ToastStore.shared.showLoading("Amending commit...")
        gitOperationService.amendCommit(
            message: message,
            onSuccess: {
                ToastStore.shared.show("Commit amended", type: .success)
            },
            onError: { [logger] error in
                ToastStore.shared.show("Amend failed: \(error.localizedDescription)", type: .error, duration: 5.0)
                logger.error("Failed to amend commit: \(error)")
            }
        )
    }

    func commitWithSignoff(_ message: String) {
        ToastStore.shared.showLoading("Committing with sign-off...")
        gitOperationService.commitWithSignoff(
            message: message,
            onSuccess: {
                ToastStore.shared.show("Changes committed", type: .success)
            },
            onError: { [logger] error in
                ToastStore.shared.show("Commit failed: \(error.localizedDescription)", type: .error, duration: 5.0)
                logger.error("Failed to commit with signoff: \(error)")
            }
        )
    }
}
