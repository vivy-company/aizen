//
//  VVLanguageBridge.swift
//  aizen
//
//  Helpers for mapping app language hints to VVCode languages.
//

import Foundation
import VVCode

nonisolated enum VVLanguageBridge {
    static func language(from hint: String?) -> VVLanguage? {
        guard var normalized = hint?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !normalized.isEmpty else {
            return nil
        }

        if normalized.hasPrefix(".") {
            normalized.removeFirst()
        }

        switch normalized {
        case "js", "jsx":
            normalized = "javascript"
        case "ts", "tsx":
            normalized = "typescript"
        case "py":
            normalized = "python"
        case "rs":
            normalized = "rust"
        case "yml":
            normalized = "yaml"
        case "md":
            normalized = "markdown"
        case "sh", "zsh", "shell":
            normalized = "bash"
        case "c++", "cc", "cxx", "hpp", "hh", "hxx":
            normalized = "cpp"
        case "htm":
            normalized = "html"
        case "docker":
            normalized = "dockerfile"
        default:
            break
        }

        if let direct = VVLanguage.allLanguages.first(where: { $0.identifier == normalized }) {
            return direct
        }

        return VVLanguage.allLanguages.first(where: { $0.fileExtensions.contains(normalized) })
    }

    static func language(fromPath path: String?) -> VVLanguage? {
        guard let path, !path.isEmpty else { return nil }
        return VVLanguage.detect(from: URL(fileURLWithPath: path))
    }

    static func language(fromMIMEType mimeType: String?) -> VVLanguage? {
        guard let mimeType = mimeType?.lowercased() else { return nil }

        switch mimeType {
        case "application/json":
            return .json
        case "application/toml":
            return .toml
        case "application/sql":
            return .sql
        case "application/x-sh", "application/x-shellscript":
            return .bash
        case "text/x-swift":
            return .swift
        case "text/x-rustsrc":
            return .rust
        case "text/x-python", "application/x-python-code":
            return .python
        case "text/javascript", "application/javascript", "application/x-javascript":
            return .javascript
        case "text/typescript", "application/x-typescript":
            return .typescript
        case "text/html":
            return .html
        case "text/css":
            return .css
        case "text/markdown":
            return .markdown
        case "text/x-diff", "text/x-patch":
            return .diff
        case "application/yaml", "text/yaml", "text/x-yaml":
            return .yaml
        default:
            return nil
        }
    }
}
