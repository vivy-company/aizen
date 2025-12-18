//
//  WorkflowTypes.swift
//  aizen
//
//  Models for CI/CD workflow management (GitHub Actions / GitLab CI)
//

import Foundation

// MARK: - Provider Detection

enum WorkflowProvider: String, CaseIterable {
    case github
    case gitlab
    case none

    var displayName: String {
        switch self {
        case .github: return "GitHub Actions"
        case .gitlab: return "GitLab CI"
        case .none: return "None"
        }
    }

    var cliCommand: String {
        switch self {
        case .github: return "gh"
        case .gitlab: return "glab"
        case .none: return ""
        }
    }
}

// MARK: - Workflow

struct Workflow: Identifiable, Hashable {
    let id: String
    let name: String
    let path: String  // .github/workflows/ci.yml or .gitlab-ci.yml
    let state: WorkflowState
    let provider: WorkflowProvider

    var canTrigger: Bool {
        state == .active
    }
}

enum WorkflowState: String {
    case active
    case disabled
    case unknown
}

// MARK: - Workflow Run

struct WorkflowRun: Identifiable, Hashable {
    let id: String
    let workflowId: String
    let workflowName: String
    let runNumber: Int
    let status: RunStatus
    let conclusion: RunConclusion?
    let branch: String
    let commit: String
    let commitMessage: String?
    let event: String  // push, pull_request, workflow_dispatch, etc.
    let actor: String  // user who triggered
    let startedAt: Date?
    let completedAt: Date?
    let url: String?

    var isInProgress: Bool {
        status == .inProgress || status == .queued || status == .pending || status == .waiting
    }

    var displayStatus: String {
        if let conclusion = conclusion {
            return conclusion.rawValue.capitalized
        }
        return status.rawValue.replacingOccurrences(of: "_", with: " ").capitalized
    }

    var statusIcon: String {
        if let conclusion = conclusion {
            switch conclusion {
            case .success: return "checkmark.circle.fill"
            case .failure: return "xmark.circle.fill"
            case .cancelled: return "stop.circle.fill"
            case .skipped: return "arrow.right.circle.fill"
            case .timedOut: return "clock.badge.exclamationmark.fill"
            case .actionRequired: return "exclamationmark.circle.fill"
            case .neutral: return "minus.circle.fill"
            }
        }
        switch status {
        case .queued, .pending, .waiting: return "clock.fill"
        case .inProgress: return "play.circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .requested: return "hourglass"
        }
    }

    var statusColor: String {
        if let conclusion = conclusion {
            switch conclusion {
            case .success: return "green"
            case .failure: return "red"
            case .cancelled: return "gray"
            case .skipped: return "gray"
            case .timedOut: return "orange"
            case .actionRequired: return "yellow"
            case .neutral: return "gray"
            }
        }
        switch status {
        case .queued, .pending, .waiting, .requested: return "yellow"
        case .inProgress: return "yellow"
        case .completed: return "green"
        }
    }
}

enum RunStatus: String, CaseIterable {
    case queued
    case inProgress = "in_progress"
    case completed
    case pending
    case waiting
    case requested
}

enum RunConclusion: String, CaseIterable {
    case success
    case failure
    case cancelled
    case skipped
    case timedOut = "timed_out"
    case actionRequired = "action_required"
    case neutral
}

// MARK: - Job & Step

struct WorkflowJob: Identifiable, Hashable {
    let id: String
    let name: String
    let status: RunStatus
    let conclusion: RunConclusion?
    let startedAt: Date?
    let completedAt: Date?
    let steps: [WorkflowStep]

    var duration: TimeInterval? {
        guard let start = startedAt else { return nil }
        let end = completedAt ?? Date()
        return end.timeIntervalSince(start)
    }

    var durationString: String {
        guard let duration = duration else { return "" }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }
}

struct WorkflowStep: Identifiable, Hashable {
    let id: String
    let number: Int
    let name: String
    let status: RunStatus
    let conclusion: RunConclusion?
    let startedAt: Date?
    let completedAt: Date?
}

// MARK: - Workflow Dispatch Inputs

struct WorkflowInput: Identifiable, Hashable {
    let id: String  // input name/key
    let description: String
    let required: Bool
    let type: WorkflowInputType
    let defaultValue: String?

    var displayName: String {
        id.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }
}

enum WorkflowInputType: Hashable {
    case string
    case boolean
    case choice([String])
    case environment

    var defaultEmptyValue: String {
        switch self {
        case .boolean: return "false"
        default: return ""
        }
    }
}

// MARK: - Logs

struct WorkflowLogLine: Identifiable, Hashable, Sendable {
    let id: Int
    let stepName: String
    let stepNumber: Int?
    let content: String
    let timestamp: Date?
    let isError: Bool
    let isGroupStart: Bool
    let isGroupEnd: Bool
    let groupName: String?

    init(
        id: Int,
        stepName: String,
        stepNumber: Int? = nil,
        content: String,
        timestamp: Date? = nil,
        isError: Bool = false,
        isGroupStart: Bool = false,
        isGroupEnd: Bool = false,
        groupName: String? = nil
    ) {
        self.id = id
        self.stepName = stepName
        self.stepNumber = stepNumber
        self.content = content
        self.timestamp = timestamp
        self.isError = isError
        self.isGroupStart = isGroupStart
        self.isGroupEnd = isGroupEnd
        self.groupName = groupName
    }
}

struct WorkflowLogs: Sendable {
    let runId: String
    let jobId: String?
    let lines: [WorkflowLogLine]
    let rawContent: String
    let lastUpdated: Date

    var content: String { rawContent }
}

// MARK: - Errors

enum WorkflowError: LocalizedError {
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
