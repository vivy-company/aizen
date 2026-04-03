import AppKit

extension WorkflowLogTableView.Coordinator {
    func rebuildDisplayRows() {
        displayRows.removeAll()
        for step in steps {
            let totalLines = step.groups.reduce(0) { $0 + $1.lines.count }
            displayRows.append(.stepHeader(id: step.id, name: step.name, groupCount: totalLines, isExpanded: step.isExpanded))

            if step.isExpanded {
                for group in step.groups {
                    if !group.title.isEmpty {
                        displayRows.append(.groupHeader(id: group.id, stepId: step.id, title: group.title, lineCount: group.lines.count, isExpanded: group.isExpanded))
                    }

                    if group.isExpanded || group.title.isEmpty {
                        for line in group.lines {
                            displayRows.append(.logLine(id: line.id, content: line.raw, attributedContent: line.attributed))
                        }
                    }
                }
            }
        }
    }

    func toggleStep(_ stepId: Int) {
        if let index = steps.firstIndex(where: { $0.id == stepId }) {
            steps[index].isExpanded.toggle()
            rebuildDisplayRows()
            tableView?.reloadData()
        }
    }

    func toggleGroup(_ groupId: Int, inStep stepId: Int) {
        if let stepIndex = steps.firstIndex(where: { $0.id == stepId }),
           let groupIndex = steps[stepIndex].groups.firstIndex(where: { $0.id == groupId }) {
            steps[stepIndex].groups[groupIndex].isExpanded.toggle()
            rebuildDisplayRows()
            tableView?.reloadData()
        }
    }

    func expandAll() {
        for i in steps.indices {
            steps[i].isExpanded = true
            for j in steps[i].groups.indices {
                steps[i].groups[j].isExpanded = true
            }
        }
        rebuildDisplayRows()
        tableView?.reloadData()
    }

    func collapseAll() {
        for i in steps.indices {
            steps[i].isExpanded = false
            for j in steps[i].groups.indices {
                steps[i].groups[j].isExpanded = false
            }
        }
        rebuildDisplayRows()
        tableView?.reloadData()
    }

    func copyAllLogs() {
        var allLines: [String] = []
        for step in steps {
            for group in step.groups {
                for line in group.lines {
                    allLines.append(line.raw)
                }
            }
        }
        Clipboard.copy(lines: allLines)
    }

    func copyStepLogs(_ stepId: Int) {
        guard let step = steps.first(where: { $0.id == stepId }) else { return }
        var lines: [String] = []
        for group in step.groups {
            for line in group.lines {
                lines.append(line.raw)
            }
        }
        Clipboard.copy(lines: lines)
    }
}
