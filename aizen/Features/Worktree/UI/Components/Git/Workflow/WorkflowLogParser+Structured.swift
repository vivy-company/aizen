//
//  WorkflowLogParser+Structured.swift
//  aizen
//
//  Created by OpenAI Codex on 06.04.26.
//

import AppKit
import Foundation

nonisolated extension WorkflowLogParser {
    static func parseStructuredLogs(_ logs: WorkflowLogs, fontSize: CGFloat) -> [LogStep] {
        var steps: [LogStep] = []
        var currentStepName = ""
        var currentGroup: LogGroup?
        var groupId = 0
        var lineId = 0
        var stepId = 0
        var currentStyle = ANSITextStyle()
        var lastGroupTitle = ""

        for logLine in logs.lines {
            let stepName = logLine.stepName

            if stepName != currentStepName {
                if let group = currentGroup, !group.lines.isEmpty, !steps.isEmpty {
                    steps[steps.count - 1].groups.append(group)
                    currentGroup = nil
                }

                currentStepName = stepName
                steps.append(LogStep(id: stepId, name: stepName, groups: [], isExpanded: false))
                stepId += 1
            }

            let currentStepIdx = steps.isEmpty ? nil : steps.count - 1

            if logLine.isGroupStart {
                if let group = currentGroup, !group.lines.isEmpty, let stepIdx = currentStepIdx {
                    steps[stepIdx].groups.append(group)
                }

                let title = logLine.groupName ?? "Output"

                if title == "Output" && !lastGroupTitle.isEmpty {
                    if let stepIdx = currentStepIdx, !steps[stepIdx].groups.isEmpty {
                        let lastIdx = steps[stepIdx].groups.count - 1
                        currentGroup = steps[stepIdx].groups[lastIdx]
                        steps[stepIdx].groups.removeLast()
                    } else {
                        currentGroup = LogGroup(id: groupId, title: lastGroupTitle, lines: [], isExpanded: false)
                        groupId += 1
                    }
                } else {
                    currentGroup = LogGroup(id: groupId, title: title, lines: [], isExpanded: false)
                    lastGroupTitle = title
                    groupId += 1
                }
            } else if logLine.isGroupEnd {
                if let group = currentGroup, let stepIdx = currentStepIdx {
                    steps[stepIdx].groups.append(group)
                    currentGroup = nil
                }
            } else if !logLine.content.trimmingCharacters(in: .whitespaces).isEmpty {
                let (attributed, newStyle) = WorkflowLogANSIFormatter.parseLineToAttributedString(
                    logLine.content,
                    style: currentStyle,
                    fontSize: fontSize
                )
                currentStyle = newStyle

                if currentGroup != nil {
                    currentGroup?.lines.append((id: lineId, raw: logLine.content, attributed: attributed))
                } else if let stepIdx = currentStepIdx {
                    if steps[stepIdx].groups.isEmpty || !steps[stepIdx].groups.last!.title.isEmpty {
                        currentGroup = LogGroup(id: groupId, title: "", lines: [], isExpanded: true)
                        groupId += 1
                    } else {
                        currentGroup = steps[stepIdx].groups.removeLast()
                    }
                    currentGroup?.lines.append((id: lineId, raw: logLine.content, attributed: attributed))
                }
                lineId += 1
            }
        }

        if let group = currentGroup, !group.lines.isEmpty, !steps.isEmpty {
            steps[steps.count - 1].groups.append(group)
        }

        return steps.filter { !$0.groups.isEmpty || $0.groups.contains { !$0.lines.isEmpty } }
    }
}
