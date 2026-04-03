import AppKit
import Foundation

nonisolated enum WorkflowLogParser {
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

    static func parseGitLabLogs(_ lines: [String], fontSize: CGFloat) -> [LogStep] {
        var groups: [LogGroup] = []
        var currentGroup: LogGroup?
        var ungroupedLines: [(id: Int, raw: String, attributed: NSAttributedString)] = []
        var groupId = 0
        var lineId = 0
        var currentStyle = ANSITextStyle()

        let sectionNames: [String: String] = [
            "prepare_executor": "Prepare Executor",
            "prepare_script": "Prepare Environment",
            "get_sources": "Get Sources",
            "step_script": "Execute Script",
            "after_script": "After Script",
            "cleanup_file_variables": "Cleanup",
            "archive_cache": "Archive Cache",
            "upload_artifacts": "Upload Artifacts",
            "download_artifacts": "Download Artifacts"
        ]

        let controlCodePattern = try? NSRegularExpression(pattern: #"\x1B\[[0-9;]*[KJHfsu]|\[0K"#, options: [])

        for line in lines {
            var cleanLine = line.replacingOccurrences(of: "\r", with: "")
            if let regex = controlCodePattern {
                cleanLine = regex.stringByReplacingMatches(
                    in: cleanLine,
                    options: [],
                    range: NSRange(cleanLine.startIndex..., in: cleanLine),
                    withTemplate: ""
                )
            }

            let trimmed = cleanLine.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("section_start:") {
                if !ungroupedLines.isEmpty {
                    let group = LogGroup(id: groupId, title: "", lines: ungroupedLines, isExpanded: true)
                    groups.append(group)
                    groupId += 1
                    ungroupedLines = []
                }

                if let group = currentGroup, !group.lines.isEmpty {
                    groups.append(group)
                }

                let parts = trimmed.split(separator: ":")
                let sectionName = parts.count >= 3 ? String(parts[2]) : "Section"
                let displayName = sectionNames[sectionName] ?? sectionName.replacingOccurrences(of: "_", with: " ").capitalized

                currentGroup = LogGroup(id: groupId, title: displayName, lines: [], isExpanded: false)
                groupId += 1
                continue
            }

            if trimmed.hasPrefix("section_end:") {
                if let group = currentGroup {
                    groups.append(group)
                    currentGroup = nil
                }
                continue
            }

            guard !trimmed.isEmpty else { continue }

            let (attributed, newStyle) = WorkflowLogANSIFormatter.parseLineToAttributedString(
                cleanLine,
                style: currentStyle,
                fontSize: fontSize
            )
            currentStyle = newStyle

            if currentGroup != nil {
                currentGroup?.lines.append((id: lineId, raw: cleanLine, attributed: attributed))
            } else {
                ungroupedLines.append((id: lineId, raw: cleanLine, attributed: attributed))
            }
            lineId += 1
        }

        if let group = currentGroup, !group.lines.isEmpty {
            groups.append(group)
        }
        if !ungroupedLines.isEmpty {
            let group = LogGroup(id: groupId, title: "", lines: ungroupedLines, isExpanded: true)
            groups.append(group)
        }

        if groups.isEmpty {
            return []
        }

        return [LogStep(id: 0, name: "Job Output", groups: groups, isExpanded: true)]
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
