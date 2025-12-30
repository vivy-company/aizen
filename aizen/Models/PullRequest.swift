//
//  PullRequest.swift
//  aizen
//
//  Models for Pull Request / Merge Request data
//

import Foundation

// MARK: - Pull Request

struct PullRequest: Identifiable, Equatable, Sendable, Hashable {
    let id: Int
    let number: Int
    let title: String
    let body: String
    let state: State
    let author: String
    let sourceBranch: String
    let targetBranch: String
    let url: String
    let createdAt: Date
    let updatedAt: Date
    let isDraft: Bool
    let mergeable: MergeableState
    let reviewDecision: ReviewDecision?
    let checksStatus: ChecksStatus?
    let additions: Int
    let deletions: Int
    let changedFiles: Int

    enum State: String, Sendable, Codable, CaseIterable {
        case open
        case merged
        case closed

        var displayName: String {
            switch self {
            case .open: return "Open"
            case .merged: return "Merged"
            case .closed: return "Closed"
            }
        }
    }

    enum MergeableState: String, Sendable, Codable {
        case mergeable
        case conflicting
        case unknown

        var isMergeable: Bool {
            self == .mergeable
        }
    }

    enum ReviewDecision: String, Sendable, Codable {
        case approved = "APPROVED"
        case changesRequested = "CHANGES_REQUESTED"
        case reviewRequired = "REVIEW_REQUIRED"

        var displayName: String {
            switch self {
            case .approved: return "Approved"
            case .changesRequested: return "Changes Requested"
            case .reviewRequired: return "Review Required"
            }
        }

        var iconName: String {
            switch self {
            case .approved: return "checkmark.circle.fill"
            case .changesRequested: return "xmark.circle.fill"
            case .reviewRequired: return "clock.fill"
            }
        }
    }

    enum ChecksStatus: String, Sendable, Codable {
        case passing = "SUCCESS"
        case failing = "FAILURE"
        case pending = "PENDING"

        var displayName: String {
            switch self {
            case .passing: return "Passing"
            case .failing: return "Failing"
            case .pending: return "Pending"
            }
        }

        var iconName: String {
            switch self {
            case .passing: return "checkmark.circle.fill"
            case .failing: return "xmark.circle.fill"
            case .pending: return "clock.fill"
            }
        }
    }

    var relativeCreatedAt: String {
        RelativeDateFormatter.shared.string(from: createdAt)
    }

    var relativeUpdatedAt: String {
        RelativeDateFormatter.shared.string(from: updatedAt)
    }
}

// MARK: - PR Comment

struct PRComment: Identifiable, Equatable, Sendable {
    let id: String
    let author: String
    let avatarURL: String?
    let body: String
    let createdAt: Date
    let isReview: Bool
    let reviewState: ReviewState?
    let path: String?
    let line: Int?

    enum ReviewState: String, Sendable, Codable {
        case approved = "APPROVED"
        case changesRequested = "CHANGES_REQUESTED"
        case commented = "COMMENTED"
        case pending = "PENDING"

        var displayName: String {
            switch self {
            case .approved: return "Approved"
            case .changesRequested: return "Changes Requested"
            case .commented: return "Commented"
            case .pending: return "Pending"
            }
        }
    }

    var relativeDate: String {
        RelativeDateFormatter.shared.string(from: createdAt)
    }
}

// MARK: - PR File

struct PRFile: Identifiable, Equatable, Sendable {
    var id: String { path }
    let path: String
    let status: Status
    let additions: Int
    let deletions: Int
    let patch: String?

    enum Status: String, Sendable, Codable {
        case added
        case modified
        case deleted
        case renamed

        var iconName: String {
            switch self {
            case .added: return "plus.circle.fill"
            case .modified: return "pencil.circle.fill"
            case .deleted: return "minus.circle.fill"
            case .renamed: return "arrow.right.circle.fill"
            }
        }
    }
}

// MARK: - PR Filter

nonisolated enum PRFilter: String, CaseIterable, Sendable {
    case open
    case merged
    case closed
    case all

    var displayName: String {
        switch self {
        case .open: return "Open"
        case .merged: return "Merged"
        case .closed: return "Closed"
        case .all: return "All"
        }
    }

    var cliValue: String {
        switch self {
        case .open: return "open"
        case .merged: return "merged"
        case .closed: return "closed"
        case .all: return "all"
        }
    }
}

// MARK: - Merge Method

enum PRMergeMethod: String, CaseIterable, Sendable {
    case merge
    case squash
    case rebase

    var displayName: String {
        switch self {
        case .merge: return "Merge"
        case .squash: return "Squash"
        case .rebase: return "Rebase"
        }
    }

    var ghFlag: String {
        "--\(rawValue)"
    }
}

// MARK: - Relative Date Formatter

private class RelativeDateFormatter {
    static let shared = RelativeDateFormatter()

    private let formatter: RelativeDateTimeFormatter

    private init() {
        formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
    }

    func string(from date: Date) -> String {
        formatter.localizedString(for: date, relativeTo: Date())
    }
}
