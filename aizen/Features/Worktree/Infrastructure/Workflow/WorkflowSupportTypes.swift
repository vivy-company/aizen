//
//  WorkflowSupportTypes.swift
//  aizen
//

import Foundation

// MARK: - Errors

nonisolated enum WorkflowError: LocalizedError {
    case providerNotDetected
    case cliNotInstalled(provider: WorkflowProvider)
    case notAuthenticated(provider: WorkflowProvider)
    case parseError(String)
    case executionFailed(String)
    case workflowNotFound(String)
    case cannotTrigger(String)

    var errorDescription: String? {
        switch self {
        case .providerNotDetected:
            return "Could not detect CI/CD provider (GitHub/GitLab)"
        case .cliNotInstalled(let provider):
            return "\(provider.cliCommand) CLI is not installed"
        case .notAuthenticated(let provider):
            return "Not authenticated with \(provider.displayName)"
        case .parseError(let message):
            return "Failed to parse response: \(message)"
        case .executionFailed(let message):
            return "Command failed: \(message)"
        case .workflowNotFound(let name):
            return "Workflow not found: \(name)"
        case .cannotTrigger(let reason):
            return "Cannot trigger workflow: \(reason)"
        }
    }
}

// MARK: - CLI Availability

struct CLIAvailability {
    let gh: Bool
    let glab: Bool
    let ghAuthenticated: Bool
    let glabAuthenticated: Bool
}
