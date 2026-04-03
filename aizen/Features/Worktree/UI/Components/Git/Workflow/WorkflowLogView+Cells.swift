import AppKit

extension WorkflowLogTableView.Coordinator {
    func makeStepHeaderCell(id: Int, name: String, count: Int, isExpanded: Bool, tableView: NSTableView) -> NSView {
        let cellId = NSUserInterfaceItemIdentifier("StepHeader")
        let cell: StepHeaderCellView
        if let existing = tableView.makeView(withIdentifier: cellId, owner: nil) as? StepHeaderCellView {
            cell = existing
        } else {
            cell = StepHeaderCellView(identifier: cellId)
        }
        cell.configure(id: id, name: name, count: count, isExpanded: isExpanded, fontSize: fontSize, onToggle: { [weak self] stepId in
            self?.toggleStep(stepId)
        }, onCopy: { [weak self] stepId in
            self?.copyStepLogs(stepId)
        })
        return cell
    }

    func makeGroupHeaderCell(id: Int, stepId: Int, title: String, count: Int, isExpanded: Bool, tableView: NSTableView) -> NSView {
        let cellId = NSUserInterfaceItemIdentifier("GroupHeader")
        let cell: GroupHeaderCellView
        if let existing = tableView.makeView(withIdentifier: cellId, owner: nil) as? GroupHeaderCellView {
            cell = existing
        } else {
            cell = GroupHeaderCellView(identifier: cellId)
        }
        cell.configure(id: id, stepId: stepId, title: title, count: count, isExpanded: isExpanded, fontSize: fontSize) { [weak self] groupId, stepId in
            self?.toggleGroup(groupId, inStep: stepId)
        }
        return cell
    }

    func makeLogLineCell(attributed: NSAttributedString, tableView: NSTableView) -> NSView {
        let cellId = NSUserInterfaceItemIdentifier("LogLine")
        let cell: LogLineCellView
        if let existing = tableView.makeView(withIdentifier: cellId, owner: nil) as? LogLineCellView {
            cell = existing
        } else {
            cell = LogLineCellView(identifier: cellId)
        }
        cell.configure(attributed: attributed)
        return cell
    }
}
