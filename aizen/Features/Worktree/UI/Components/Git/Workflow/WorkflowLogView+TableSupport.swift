import AppKit

extension WorkflowLogTableView.Coordinator {
    var frameObserver: NSObjectProtocol? {
        get { workflowLogFrameObserver }
        set { workflowLogFrameObserver = newValue }
    }

    var columnObserver: NSObjectProtocol? {
        get { workflowLogColumnObserver }
        set { workflowLogColumnObserver = newValue }
    }

    var lastTableWidth: CGFloat {
        get { workflowLogLastTableWidth }
        set { workflowLogLastTableWidth = newValue }
    }

    func observeFrameChanges(_ tableView: NSTableView) {
        lastTableWidth = tableView.bounds.width
        tableView.postsFrameChangedNotifications = true

        if let clipView = tableView.enclosingScrollView?.contentView {
            clipView.postsBoundsChangedNotifications = true
            frameObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: clipView,
                queue: .main
            ) { [weak self, weak tableView] _ in
                self?.handleWidthChange(tableView)
            }
        } else {
            frameObserver = NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: tableView,
                queue: .main
            ) { [weak self, weak tableView] _ in
                self?.handleWidthChange(tableView)
            }
        }

        columnObserver = NotificationCenter.default.addObserver(
            forName: NSTableView.columnDidResizeNotification,
            object: tableView,
            queue: .main
        ) { [weak self, weak tableView] _ in
            self?.handleWidthChange(tableView)
        }
    }

    func handleWidthChange(_ tableView: NSTableView?) {
        guard let tableView = tableView else { return }
        let newWidth = tableView.tableColumns.first?.width ?? tableView.bounds.width
        if abs(newWidth - lastTableWidth) > 5 {
            lastTableWidth = newWidth
            let rowCount = displayRows.count
            if rowCount > 0 {
                tableView.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<rowCount))
            }
        }
    }

    func getSelectedContent() -> String {
        guard let tableView = tableView else { return "" }
        var lines: [String] = []
        for rowIndex in tableView.selectedRowIndexes {
            guard rowIndex < displayRows.count else { continue }
            switch displayRows[rowIndex] {
            case .logLine(_, let content, _):
                lines.append(content)
            case .groupHeader(_, _, let title, _, _):
                lines.append("[\(title)]")
            case .stepHeader(_, let name, _, _):
                lines.append("== \(name) ==")
            }
        }
        return lines.joined(separator: "\n")
    }

    func selectedCopyText() -> String {
        getSelectedContent()
    }
}
