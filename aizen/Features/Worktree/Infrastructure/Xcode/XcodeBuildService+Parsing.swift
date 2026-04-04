//
//  XcodeBuildService+Parsing.swift
//  aizen
//
//  Parsing helpers for build progress and xcodebuild diagnostics
//

import Foundation

extension XcodeBuildService {
    // MARK: - Progress Parsing

    nonisolated func parseProgress(from output: String) -> String? {
        let lines = output.components(separatedBy: "\n")

        for line in lines.reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("CompileSwift"),
               let fileName = extractFileName(from: trimmed) {
                return "Compiling \(fileName)"
            }

            if trimmed.hasPrefix("CompileC"),
               let fileName = extractFileName(from: trimmed) {
                return "Compiling \(fileName)"
            }

            if trimmed.hasPrefix("Ld ") {
                return "Linking..."
            }

            if trimmed.hasPrefix("CodeSign ") {
                return "Signing..."
            }

            if trimmed.hasPrefix("ProcessInfoPlistFile") {
                return "Processing Info.plist"
            }

            if trimmed.hasPrefix("CopySwiftLibs") {
                return "Copying Swift libraries"
            }

            if trimmed.hasPrefix("Touch ") {
                return "Finishing..."
            }
        }

        return nil
    }

    nonisolated func extractFileName(from line: String) -> String? {
        let components = line.components(separatedBy: " ")
        for component in components.reversed() {
            if component.hasSuffix(".swift") || component.hasSuffix(".m") ||
                component.hasSuffix(".mm") || component.hasSuffix(".c") ||
                component.hasSuffix(".cpp") {
                return (component as NSString).lastPathComponent
            }
        }
        return nil
    }

    // MARK: - Error Parsing

    nonisolated func parseBuildErrors(from log: String) -> [BuildError] {
        var errors: [BuildError] = []
        let lines = log.components(separatedBy: "\n")

        for line in lines {
            let pattern = #"(.+?):(\d+):(\d+)?:?\s*(error|warning|note):\s*(.+)"#

            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: line, options: [], range: NSRange(line.startIndex..., in: line)) {
                let file = match.range(at: 1).location != NSNotFound ?
                    String(line[Range(match.range(at: 1), in: line)!]) : nil

                let lineNum = match.range(at: 2).location != NSNotFound ?
                    Int(String(line[Range(match.range(at: 2), in: line)!])) : nil

                let column = match.range(at: 3).location != NSNotFound ?
                    Int(String(line[Range(match.range(at: 3), in: line)!])) : nil

                let typeStr = match.range(at: 4).location != NSNotFound ?
                    String(line[Range(match.range(at: 4), in: line)!]) : "error"

                let message = match.range(at: 5).location != NSNotFound ?
                    String(line[Range(match.range(at: 5), in: line)!]) : line

                let errorType: BuildError.ErrorType
                switch typeStr.lowercased() {
                case "warning": errorType = .warning
                case "note": errorType = .note
                default: errorType = .error
                }

                let error = BuildError(
                    file: file.flatMap { ($0 as NSString).lastPathComponent },
                    line: lineNum,
                    column: column,
                    message: message,
                    type: errorType
                )
                errors.append(error)
            }
        }

        errors.sort { lhs, rhs in
            let order: [BuildError.ErrorType: Int] = [.error: 0, .warning: 1, .note: 2]
            return (order[lhs.type] ?? 0) < (order[rhs.type] ?? 0)
        }

        return errors
    }
}
