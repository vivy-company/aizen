//
//  WorkflowLogView+Coordinator.swift
//  aizen
//
//  Created by OpenAI Codex on 06.04.26.
//

import AppKit
import SwiftUI

extension WorkflowLogTableView.Coordinator {
    func parseLogs(_ logs: String, structuredLogs: WorkflowLogs? = nil, fontSize: CGFloat, showTimestamps: Bool, provider: WorkflowProvider = .github) {
        currentLogs = logs
        self.fontSize = fontSize
        self.showTimestamps = showTimestamps

        parseTask?.cancel()
        let logsSnapshot = logs
        let structuredSnapshot = structuredLogs
        let fontSizeSnapshot = fontSize
        let providerSnapshot = provider

        parseTask = Task.detached(priority: .userInitiated) {
            let parsed: [LogStep]
            if let structured = structuredSnapshot, !structured.lines.isEmpty {
                parsed = WorkflowLogParser.parseStructuredLogs(structured, fontSize: fontSizeSnapshot)
            } else {
                parsed = WorkflowLogParser.parseLogSteps(
                    logsSnapshot,
                    fontSize: fontSizeSnapshot,
                    provider: providerSnapshot
                )
            }

            await MainActor.run { [weak self] in
                guard let self = self else { return }
                self.steps = parsed
                self.rebuildDisplayRows()
                self.tableView?.reloadData()

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.recalculateAllHeights()
                }
            }
        }
    }

    func recalculateAllHeights() {
        guard let tableView = tableView, displayRows.count > 0 else { return }
        tableView.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<displayRows.count))
    }
}
