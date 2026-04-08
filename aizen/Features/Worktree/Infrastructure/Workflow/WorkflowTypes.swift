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
