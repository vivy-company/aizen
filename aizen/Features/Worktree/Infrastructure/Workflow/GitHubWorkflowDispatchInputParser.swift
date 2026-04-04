//
//  GitHubWorkflowDispatchInputParser.swift
//  aizen
//
//  Created by OpenAI Codex on 05.04.26.
//

import Foundation

nonisolated enum GitHubWorkflowDispatchInputParser {
    static func parse(yaml: String) -> [WorkflowInput] {
        var inputs: [WorkflowInput] = []

        let lines = yaml.components(separatedBy: .newlines)
        var inInputs = false
        var inputsBaseIndent = 0
        var currentInput: String?
        var currentDescription = ""
        var currentRequired = false
        var currentDefault: String?
        var currentType: WorkflowInputType = .string
        var currentOptions: [String] = []

        func saveCurrentInput() {
            if let name = currentInput, !name.isEmpty {
                inputs.append(WorkflowInput(
                    id: name,
                    description: currentDescription,
                    required: currentRequired,
                    type: currentType,
                    defaultValue: currentDefault
                ))
            }
            currentInput = nil
            currentDescription = ""
            currentRequired = false
            currentDefault = nil
            currentType = .string
            currentOptions = []
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            let indent = line.prefix(while: { $0 == " " }).count

            if trimmed == "inputs:" || trimmed.hasPrefix("inputs:") {
                if indent >= 4 && indent <= 6 {
                    inInputs = true
                    inputsBaseIndent = indent
                    continue
                }
            }

            if inInputs {
                let inputNameIndent = inputsBaseIndent + 2
                let propertyIndent = inputsBaseIndent + 4

                if indent <= inputsBaseIndent && !trimmed.hasPrefix("-") {
                    saveCurrentInput()
                    inInputs = false
                    continue
                }

                if indent == inputNameIndent && trimmed.hasSuffix(":") {
                    let potentialName = String(trimmed.dropLast())
                    if !potentialName.contains(" ") && !potentialName.contains("'") {
                        saveCurrentInput()
                        currentInput = potentialName
                        continue
                    }
                }

                if indent >= propertyIndent && currentInput != nil {
                    if trimmed.hasPrefix("description:") {
                        currentDescription = extractValue(trimmed, key: "description")
                    } else if trimmed.hasPrefix("required:") {
                        currentRequired = extractValue(trimmed, key: "required").lowercased() == "true"
                    } else if trimmed.hasPrefix("default:") {
                        currentDefault = extractValue(trimmed, key: "default")
                    } else if trimmed.hasPrefix("type:") {
                        let typeString = extractValue(trimmed, key: "type")
                        switch typeString.lowercased() {
                        case "boolean": currentType = .boolean
                        case "choice": currentType = .choice([])
                        case "environment": currentType = .environment
                        default: currentType = .string
                        }
                    } else if trimmed.hasPrefix("options:") {
                        currentOptions = []
                    } else if trimmed.hasPrefix("- ") {
                        if case .choice = currentType {
                            let option = String(trimmed.dropFirst(2)).trimmingCharacters(in: .init(charactersIn: "'\""))
                            currentOptions.append(option)
                            currentType = .choice(currentOptions)
                        }
                    }
                }
            }
        }

        saveCurrentInput()
        return inputs
    }

    private static func extractValue(_ line: String, key: String) -> String {
        let parts = line.components(separatedBy: ":")
        guard parts.count >= 2 else { return "" }
        return parts.dropFirst().joined(separator: ":")
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: .init(charactersIn: "'\""))
    }
}
