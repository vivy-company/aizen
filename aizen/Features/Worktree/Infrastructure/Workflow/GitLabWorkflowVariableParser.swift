//
//  GitLabWorkflowVariableParser.swift
//  aizen
//

import Foundation

enum GitLabWorkflowVariableParser {
    nonisolated static func parse(yaml: String) -> [WorkflowInput] {
        var seenNames: Set<String> = []
        var inputs: [WorkflowInput] = []
        let lines = yaml.components(separatedBy: .newlines)

        var inVariables = false
        var variableIndent = 0

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let indent = line.prefix(while: { $0 == " " }).count

            if trimmed.hasPrefix("variables:") && !trimmed.contains("$") {
                inVariables = true
                variableIndent = indent + 2
                continue
            }

            if inVariables {
                if indent < variableIndent && !trimmed.isEmpty {
                    inVariables = false
                    continue
                }

                if indent == variableIndent && trimmed.contains(":") {
                    let parts = trimmed.split(separator: ":", maxSplits: 1)
                    if parts.count >= 1 {
                        let name = String(parts[0]).trimmingCharacters(in: .whitespaces)
                        let defaultValue = parts.count > 1
                            ? String(parts[1]).trimmingCharacters(in: .whitespaces).trimmingCharacters(in: .init(charactersIn: "'\""))
                            : nil

                        guard !name.hasPrefix("CI_"), !name.hasPrefix("GITLAB_") else { continue }
                        guard !seenNames.contains(name) else { continue }

                        seenNames.insert(name)
                        inputs.append(WorkflowInput(
                            id: name,
                            description: "",
                            required: false,
                            type: .string,
                            defaultValue: defaultValue
                        ))
                    }
                }
            }
        }

        return inputs
    }
}
