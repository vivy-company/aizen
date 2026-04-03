import SwiftUI

extension WorktreeCreateSheet {
    func suggestEnvironmentName() {
        generateRandomName()
    }

    func generateRandomName() {
        let excludedNames = Set(existingWorktreeNames)
        let generated = WorkspaceNameGenerator.generateUniqueName(excluding: Array(excludedNames))
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "'", with: "")
        environmentName = generated
        branchName = generated
        validateBranchName()
    }

    func validateBranchName() {
        guard mode == .linked else {
            validationWarning = nil
            return
        }

        guard !branchName.isEmpty else {
            validationWarning = nil
            return
        }

        if existingWorktreeNames.contains(branchName) {
            validationWarning = String(localized: "worktree.create.branchExists \(branchName)")
        } else {
            validationWarning = nil
        }
    }
}
