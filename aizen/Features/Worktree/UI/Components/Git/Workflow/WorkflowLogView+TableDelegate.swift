import AppKit

extension WorkflowLogTableView.Coordinator {
    func numberOfRows(in tableView: NSTableView) -> Int {
        displayRows.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < displayRows.count else { return nil }

        switch displayRows[row] {
        case .stepHeader(let id, let name, let count, let isExpanded):
            return makeStepHeaderCell(id: id, name: name, count: count, isExpanded: isExpanded, tableView: tableView)
        case .groupHeader(let id, let stepId, let title, let count, let isExpanded):
            return makeGroupHeaderCell(id: id, stepId: stepId, title: title, count: count, isExpanded: isExpanded, tableView: tableView)
        case .logLine(_, _, let attributed):
            return makeLogLineCell(attributed: attributed, tableView: tableView)
        }
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard row < displayRows.count else { return 20 }
        switch displayRows[row] {
        case .stepHeader: return 28
        case .groupHeader: return 22
        case .logLine(_, _, let attributed):
            let columnWidth = tableView.tableColumns.first?.width ?? tableView.bounds.width
            let textWidth = max(columnWidth - 20, 100)

            let textStorage = NSTextStorage(attributedString: attributed)
            let textContainer = NSTextContainer(size: NSSize(width: textWidth, height: .greatestFiniteMagnitude))
            let layoutManager = NSLayoutManager()

            textContainer.lineFragmentPadding = 0
            layoutManager.addTextContainer(textContainer)
            textStorage.addLayoutManager(layoutManager)

            layoutManager.ensureLayout(for: textContainer)
            let textHeight = layoutManager.usedRect(for: textContainer).height

            return max(ceil(textHeight) + 4, 16)
        }
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rowView = LogRowView()
        if row < displayRows.count {
            switch displayRows[row] {
            case .stepHeader: rowView.isHeader = true; rowView.isStepHeader = true
            case .groupHeader: rowView.isHeader = true; rowView.isStepHeader = false
            case .logLine: rowView.isHeader = false
            }
        }
        return rowView
    }
}
