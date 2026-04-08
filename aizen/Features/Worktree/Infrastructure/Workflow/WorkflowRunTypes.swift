//
//  WorkflowRunTypes.swift
//  aizen
//

import Foundation

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
