//
//  WorkflowLogView.swift
//  aizen
//
//  NSTableView-based log viewer for workflow logs with collapsible groups
//

import SwiftUI
import AppKit

// MARK: - NSViewRepresentable Log Table

struct WorkflowLogTableView: NSViewRepresentable {
    let logs: String
    let structuredLogs: WorkflowLogs?
    let fontSize: CGFloat
    let provider: WorkflowProvider
    @Binding var showTimestamps: Bool
    var onCoordinatorReady: ((Coordinator) -> Void)?

    func makeNSView(context: Context) -> NSScrollView {
        onCoordinatorReady?(context.coordinator)
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let tableView = CopyableTableView()
        tableView.copyProvider = context.coordinator
        context.coordinator.tableView = tableView

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("LogColumn"))
        column.minWidth = 100
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)

        // Make column fill available width
        tableView.sizeLastColumnToFit()

        tableView.headerView = nil
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.backgroundColor = NSColor.textBackgroundColor
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.allowsMultipleSelection = true
        tableView.style = .plain
        tableView.gridStyleMask = []
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle

        // Observe frame changes to recalculate row heights
        context.coordinator.observeFrameChanges(tableView)

        scrollView.documentView = tableView

        // Parse logs in background
        context.coordinator.parseLogs(logs, structuredLogs: structuredLogs, fontSize: fontSize, showTimestamps: showTimestamps, provider: provider)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        if context.coordinator.currentLogs != logs {
            context.coordinator.parseLogs(logs, structuredLogs: structuredLogs, fontSize: fontSize, showTimestamps: showTimestamps, provider: provider)
        }
        if context.coordinator.showTimestamps != showTimestamps {
            context.coordinator.showTimestamps = showTimestamps
            context.coordinator.tableView?.reloadData()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource, CopyableTableViewProvider {
        weak var tableView: NSTableView?
        var steps: [LogStep] = []
        var displayRows: [LogRow] = []
        var currentLogs: String = ""
        var fontSize: CGFloat = 11
        var showTimestamps: Bool = false

        var parseTask: Task<Void, Never>?

        var workflowLogFrameObserver: NSObjectProtocol?
        var workflowLogColumnObserver: NSObjectProtocol?
        var workflowLogLastTableWidth: CGFloat = 0

        deinit {
            if let observer = workflowLogFrameObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            if let observer = workflowLogColumnObserver {
                NotificationCenter.default.removeObserver(observer)
            }
        }

    }
}

// MARK: - SwiftUI Wrapper

struct WorkflowLogView: View {
    let logs: String
    let structuredLogs: WorkflowLogs?
    let fontSize: CGFloat
    let provider: WorkflowProvider

    @State private var showTimestamps: Bool = false

    init(_ logs: String, structuredLogs: WorkflowLogs? = nil, fontSize: CGFloat = 11, provider: WorkflowProvider = .github) {
        self.logs = logs
        self.structuredLogs = structuredLogs
        self.fontSize = fontSize
        self.provider = provider
    }

    var body: some View {
        WorkflowLogTableView(logs: logs, structuredLogs: structuredLogs, fontSize: fontSize, provider: provider, showTimestamps: $showTimestamps, onCoordinatorReady: nil)
            .background(Color(nsColor: .textBackgroundColor))
    }
}
