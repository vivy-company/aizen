//
//  WorkflowLogModels.swift
//  aizen
//
//  Models for workflow log parsing and display
//

import AppKit

// MARK: - Log Row Model

nonisolated enum LogRow {
    case stepHeader(id: Int, name: String, groupCount: Int, isExpanded: Bool)
    case groupHeader(id: Int, stepId: Int, title: String, lineCount: Int, isExpanded: Bool)
    case logLine(id: Int, content: String, attributedContent: NSAttributedString)
}

// MARK: - Log Group Model

nonisolated struct LogGroup {
    let id: Int
    let title: String
    var lines: [(id: Int, raw: String, attributed: NSAttributedString)]
    var isExpanded: Bool = false
}

// MARK: - Log Step Model

nonisolated struct LogStep {
    let id: Int
    let name: String
    var groups: [LogGroup]
    var isExpanded: Bool = false
}
