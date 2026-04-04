//
//  GitHubWorkflowProvider+StructuredLogs.swift
//  aizen
//

import Foundation

extension GitHubWorkflowProvider {
    func getStructuredLogs(repoPath: String, runId: String, jobId: String, steps: [WorkflowStep]) async throws -> WorkflowLogs {
        let result = try await executeGH(["api", "repos/{owner}/{repo}/actions/jobs/\(jobId)/logs"], workingDirectory: repoPath)
        let rawLogs = result.stdout

        let sortedSteps = steps.sorted { first, second in
            guard let firstStart = first.startedAt, let secondStart = second.startedAt else {
                return first.number > second.number
            }
            return firstStart > secondStart
        }

        var logLines: [WorkflowLogLine] = []
        logLines.reserveCapacity(rawLogs.count / 80)

        let lines = rawLogs.components(separatedBy: .newlines)
        var lineIndex = 0

        for line in lines {
            guard !line.isEmpty else { continue }

            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            var timestamp: Date?
            var content = line

            if let match = Self.timestampRegex?.firstMatch(in: line, range: range),
               let timestampRange = Range(match.range(at: 1), in: line) {
                let timestampString = String(line[timestampRange])
                timestamp = ISO8601DateParser.shared.parse(timestampString + "Z")

                if let fullRange = Range(match.range, in: line) {
                    content = String(line[fullRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                    if content.hasPrefix("."),
                       let spaceIndex = content.firstIndex(of: " ") {
                        content = String(content[content.index(after: spaceIndex)...])
                    }
                }
            }

            var stepName = "Setup"
            var stepNumber: Int?

            if let timestamp {
                for step in sortedSteps {
                    if let stepStart = step.startedAt, timestamp >= stepStart {
                        stepName = step.name
                        stepNumber = step.number
                        break
                    }
                }
            }

            let isError = content.contains("##[error]")
            let isGroupStart = content.contains("##[group]")
            let isGroupEnd = content.contains("##[endgroup]")
            var groupName: String?

            if isGroupStart {
                groupName = content.replacingOccurrences(of: "##[group]", with: "")
            }

            content = content
                .replacingOccurrences(of: "##[error]", with: "")
                .replacingOccurrences(of: "##[warning]", with: "")
                .replacingOccurrences(of: "##[group]", with: "")
                .replacingOccurrences(of: "##[endgroup]", with: "")

            logLines.append(WorkflowLogLine(
                id: lineIndex,
                stepName: stepName,
                stepNumber: stepNumber,
                content: content,
                timestamp: timestamp,
                isError: isError,
                isGroupStart: isGroupStart,
                isGroupEnd: isGroupEnd,
                groupName: groupName
            ))
            lineIndex += 1
        }

        return WorkflowLogs(
            runId: runId,
            jobId: jobId,
            lines: logLines,
            rawContent: rawLogs,
            lastUpdated: Date()
        )
    }
}
