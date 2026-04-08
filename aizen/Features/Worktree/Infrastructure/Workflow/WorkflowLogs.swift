//
//  WorkflowLogs.swift
//  aizen
//
//  Log models for CI/CD workflow runs.
//

import Foundation

nonisolated struct WorkflowLogLine: Identifiable, Hashable, Sendable {
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

nonisolated struct WorkflowLogs: Sendable {
    let runId: String
    let jobId: String?
    let lines: [WorkflowLogLine]
    let rawContent: String
    let lastUpdated: Date

    var content: String { rawContent }
}
