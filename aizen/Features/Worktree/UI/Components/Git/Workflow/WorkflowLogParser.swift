import AppKit
import Foundation

nonisolated enum WorkflowLogParser {
    static func parseLogSteps(_ text: String, fontSize: CGFloat, provider: WorkflowProvider = .github) -> [LogStep] {
        let lines = text.components(separatedBy: "\n")
        var steps: [LogStep] = []
        var stepNameCounts: [String: Int] = [:]
        var currentStepName = ""
        var currentGroup: LogGroup?
        var groupId = 0
        var lineId = 0
        var stepId = 0
        var currentStyle = ANSITextStyle()
        var lastGroupTitle = ""

        if provider == .gitlab {
            return parseGitLabLogs(lines, fontSize: fontSize)
        }

        for line in lines {
            let (extractedStep, message) = extractStepAndMessage(line)

            if !extractedStep.isEmpty && extractedStep != currentStepName {
                if let group = currentGroup, !group.lines.isEmpty, !steps.isEmpty {
                    steps[steps.count - 1].groups.append(group)
                    currentGroup = nil
                }

                currentStepName = extractedStep

                let count = stepNameCounts[extractedStep, default: 0]
                stepNameCounts[extractedStep] = count + 1

                let displayName = count > 0 ? "\(extractedStep) (\(count + 1))" : extractedStep
                steps.append(LogStep(id: stepId, name: displayName, groups: [], isExpanded: false))
                stepId += 1
            }

            let currentStepIdx = steps.isEmpty ? nil : steps.count - 1

            if message.contains("##[group]") {
                if let group = currentGroup, !group.lines.isEmpty, let stepIdx = currentStepIdx {
                    steps[stepIdx].groups.append(group)
                }

                var title = "Output"
                if let range = message.range(of: "##[group]") {
                    title = String(message[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                    if title.isEmpty { title = "Output" }
                }

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
            } else if message.contains("##[endgroup]") {
                if let group = currentGroup, let stepIdx = currentStepIdx {
                    steps[stepIdx].groups.append(group)
                    currentGroup = nil
                }
            } else if !message.trimmingCharacters(in: .whitespaces).isEmpty {
                let (attributed, newStyle) = WorkflowLogANSIFormatter.parseLineToAttributedString(
                    message,
                    style: currentStyle,
                    fontSize: fontSize
                )
                currentStyle = newStyle

                if currentGroup != nil {
                    currentGroup?.lines.append((id: lineId, raw: message, attributed: attributed))
                } else if let stepIdx = currentStepIdx {
                    if steps[stepIdx].groups.isEmpty || !steps[stepIdx].groups.last!.title.isEmpty {
                        currentGroup = LogGroup(id: groupId, title: "", lines: [], isExpanded: true)
                        groupId += 1
                    } else {
                        currentGroup = steps[stepIdx].groups.removeLast()
                    }
                    currentGroup?.lines.append((id: lineId, raw: message, attributed: attributed))
                }
                lineId += 1
            }
        }

        if let group = currentGroup, !group.lines.isEmpty, !steps.isEmpty {
            steps[steps.count - 1].groups.append(group)
        }

        return steps.filter { !$0.groups.isEmpty || $0.groups.contains { !$0.lines.isEmpty } }
    }

    static func extractStepAndMessage(_ line: String) -> (step: String, message: String) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let timestampPattern = #"(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d+Z)"#
        guard let regex = try? NSRegularExpression(pattern: timestampPattern, options: []) else {
            return ("", trimmed)
        }

        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        guard let match = regex.firstMatch(in: trimmed, options: [], range: range),
              let timestampRange = Range(match.range, in: trimmed) else {
            return ("", trimmed)
        }

        let beforeTimestamp = String(trimmed[..<timestampRange.lowerBound]).trimmingCharacters(in: .whitespaces)
        let afterTimestamp = String(trimmed[timestampRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        let parts = beforeTimestamp.split(omittingEmptySubsequences: true) { $0.isWhitespace }

        var stepName = ""
        if parts.count >= 2 {
            stepName = parts[1..<parts.count].joined(separator: " ")
        }

        return (stepName, afterTimestamp)
    }
}
