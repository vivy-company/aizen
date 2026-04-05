import AppKit
import Foundation

nonisolated extension WorkflowLogParser {
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
}
