//
//  SemanticContentParser.swift
//  aizen
//
//  Parser for detecting semantic content patterns (admonitions, errors, commands)
//

import Foundation

// MARK: - Parsed Content Types

enum ParsedContentBlock: Identifiable {
    case text(String)
    case semantic(type: SemanticBlockType, title: String?, content: String)
    case command(command: String, output: String?, exitCode: ExitCodeStatus)
    
    var id: String {
        switch self {
        case .text(let content):
            return "text-\(content.hashValue)"
        case .semantic(let type, let title, let content):
            return "semantic-\(type)-\(title ?? "")-\(content.hashValue)"
        case .command(let command, _, _):
            return "command-\(command.hashValue)"
        }
    }
}

// MARK: - Semantic Content Parser

struct SemanticContentParser {
    
    static func parse(_ content: String) -> [ParsedContentBlock] {
        var blocks: [ParsedContentBlock] = []
        var currentText = ""
        let lines = content.components(separatedBy: "\n")
        var i = 0
        
        while i < lines.count {
            let line = lines[i]
            
            if let admonition = parseAdmonitionStart(line) {
                if !currentText.isEmpty {
                    blocks.append(.text(currentText.trimmingCharacters(in: .whitespacesAndNewlines)))
                    currentText = ""
                }
                
                var admonitionContent: [String] = []
                i += 1
                
                while i < lines.count {
                    let nextLine = lines[i]
                    if nextLine.hasPrefix("> ") {
                        admonitionContent.append(String(nextLine.dropFirst(2)))
                        i += 1
                    } else if nextLine.trimmingCharacters(in: .whitespaces).isEmpty {
                        i += 1
                        break
                    } else {
                        break
                    }
                }
                
                blocks.append(.semantic(
                    type: admonition.type,
                    title: admonition.title,
                    content: admonitionContent.joined(separator: "\n")
                ))
                continue
            }
            
            if let errorPattern = detectErrorPattern(line) {
                if !currentText.isEmpty {
                    blocks.append(.text(currentText.trimmingCharacters(in: .whitespacesAndNewlines)))
                    currentText = ""
                }
                
                var errorContent: [String] = [line]
                i += 1
                
                while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                    if isErrorContinuation(lines[i]) {
                        errorContent.append(lines[i])
                        i += 1
                    } else {
                        break
                    }
                }
                
                blocks.append(.semantic(
                    type: .error,
                    title: errorPattern,
                    content: errorContent.joined(separator: "\n")
                ))
                continue
            }
            
            currentText += (currentText.isEmpty ? "" : "\n") + line
            i += 1
        }
        
        if !currentText.isEmpty {
            blocks.append(.text(currentText.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        
        return blocks.filter { block in
            switch block {
            case .text(let content):
                return !content.isEmpty
            default:
                return true
            }
        }
    }
    
    private static func parseAdmonitionStart(_ line: String) -> (type: SemanticBlockType, title: String?)? {
        let patterns: [(pattern: String, type: SemanticBlockType)] = [
            ("> [!NOTE]", .note),
            ("> [!TIP]", .info),
            ("> [!INFO]", .info),
            ("> [!IMPORTANT]", .warning),
            ("> [!WARNING]", .warning),
            ("> [!CAUTION]", .warning),
            ("> [!ERROR]", .error),
            ("> [!DANGER]", .error),
            ("> [!SUCCESS]", .success),
            ("> **Note:**", .note),
            ("> **Tip:**", .info),
            ("> **Info:**", .info),
            ("> **Warning:**", .warning),
            ("> **Important:**", .warning),
            ("> **Error:**", .error),
            ("> **Success:**", .success),
        ]
        
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        
        for (pattern, type) in patterns {
            if trimmed.lowercased().hasPrefix(pattern.lowercased()) {
                let remainder = String(trimmed.dropFirst(pattern.count)).trimmingCharacters(in: .whitespaces)
                let title = remainder.isEmpty ? nil : remainder
                return (type, title)
            }
        }
        
        return nil
    }
    
    private static func detectErrorPattern(_ line: String) -> String? {
        let errorPatterns = [
            "error:",
            "Error:",
            "ERROR:",
            "failed:",
            "Failed:",
            "FAILED:",
            "exception:",
            "Exception:",
            "EXCEPTION:",
            "fatal:",
            "Fatal:",
            "FATAL:",
            "panic:",
            "Panic:",
            "PANIC:",
            "Traceback (most recent call last):",
            "SyntaxError:",
            "TypeError:",
            "ValueError:",
            "RuntimeError:",
            "ModuleNotFoundError:",
            "ImportError:",
            "AttributeError:",
            "KeyError:",
            "IndexError:",
            "NameError:",
            "FileNotFoundError:",
            "CompileError:",
            "Build failed",
            "Compilation failed",
        ]
        
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        
        for pattern in errorPatterns {
            if trimmed.contains(pattern) {
                return pattern.replacingOccurrences(of: ":", with: "").trimmingCharacters(in: .whitespaces)
            }
        }
        
        return nil
    }
    
    private static func isErrorContinuation(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        
        if trimmed.hasPrefix("at ") { return true }
        if trimmed.hasPrefix("File \"") { return true }
        if trimmed.hasPrefix("  ") { return true }
        if trimmed.hasPrefix("\t") { return true }
        if trimmed.hasPrefix("^") { return true }
        if trimmed.hasPrefix("|") { return true }
        if trimmed.contains("line ") && trimmed.contains(":") { return true }
        
        return false
    }
}

// MARK: - Convenience Extensions

extension String {
    func parseSemanticBlocks() -> [ParsedContentBlock] {
        SemanticContentParser.parse(self)
    }
}
