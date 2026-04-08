//
//  WorkflowTypes.swift
//  aizen
//
//  Models for CI/CD workflow management (GitHub Actions / GitLab CI)
//

import Foundation

// MARK: - Provider Detection

nonisolated enum WorkflowProvider: String, CaseIterable {
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
    let supportsManualTrigger: Bool

    var canTrigger: Bool {
        state == .active && supportsManualTrigger
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
