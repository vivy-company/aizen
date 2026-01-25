//
//  ThemedInlineCode.swift
//  aizen
//
//  Theme-aware inline code rendering using Ghostty terminal colors
//

import SwiftUI
import AppKit

struct MarkdownThemeProvider {
    
    var cyan: NSColor { ANSIColorProvider.shared.nsColor(for: 6) }
    var yellow: NSColor { ANSIColorProvider.shared.nsColor(for: 3) }
    var green: NSColor { ANSIColorProvider.shared.nsColor(for: 2) }
    var magenta: NSColor { ANSIColorProvider.shared.nsColor(for: 5) }
    var red: NSColor { ANSIColorProvider.shared.nsColor(for: 1) }
    var blue: NSColor { ANSIColorProvider.shared.nsColor(for: 4) }
    var orange: NSColor { ANSIColorProvider.shared.nsColor(for: 9) }
    var brightCyan: NSColor { ANSIColorProvider.shared.nsColor(for: 14) }
    var muted: NSColor { ANSIColorProvider.shared.nsColor(for: 8) }
    var brightYellow: NSColor { ANSIColorProvider.shared.nsColor(for: 11) }
    var brightMagenta: NSColor { ANSIColorProvider.shared.nsColor(for: 13) }
    
    var codeBackground: NSColor {
        let base = ANSIColorProvider.shared.nsColor(for: 0)
        return base.withAlphaComponent(0.3)
    }
    
    var strongColor: NSColor { brightYellow }
    var emphasisColor: NSColor { brightCyan }
    var listMarkerColor: NSColor { muted }
}

enum InlineCodeType {
    case filePath
    case functionCall
    case typeOrClass
    case keyword
    case number
    case errorType
    case successKeyword
    case testResult
    case variable
    case plain
    
    func color(theme: MarkdownThemeProvider) -> NSColor {
        switch self {
        case .filePath: return theme.cyan
        case .functionCall: return theme.yellow
        case .typeOrClass: return theme.magenta
        case .keyword: return theme.blue
        case .number: return theme.orange
        case .errorType: return theme.red
        case .successKeyword: return theme.green
        case .testResult: return theme.green
        case .variable: return theme.brightCyan
        case .plain: return theme.cyan
        }
    }
}

struct InlineCodeClassifier {
    
    private static let fileExtensions = Set([
        "py", "js", "ts", "tsx", "jsx", "swift", "rs", "go", "java", "kt",
        "rb", "php", "c", "cpp", "h", "hpp", "cs", "m", "mm", "sh", "bash",
        "zsh", "fish", "json", "yaml", "yml", "toml", "xml", "html", "css",
        "scss", "less", "md", "txt", "log", "env", "gitignore", "dockerfile",
        "makefile", "gradle", "pom"
    ])
    
    private static let pythonTypes = Set([
        "int", "float", "str", "bool", "list", "dict", "tuple", "set",
        "None", "True", "False", "bytes", "object", "type", "Exception"
    ])
    
    private static let commonTypes = Set([
        "String", "Int", "Float", "Double", "Bool", "Array", "Dictionary",
        "Set", "Optional", "Result", "Error", "void", "null", "undefined",
        "number", "string", "boolean", "any", "never", "unknown", "Promise",
        "View", "State", "Binding", "ObservedObject", "StateObject", "Published",
        "ObservableObject", "Identifiable", "Equatable", "Hashable", "Codable"
    ])
    
    private static let errorTypes = Set([
        "Error", "Exception", "ValueError", "TypeError", "KeyError",
        "IndexError", "AttributeError", "ImportError", "RuntimeError",
        "IOError", "FileNotFoundError", "PermissionError", "OSError",
        "AssertionError", "SyntaxError", "NameError", "ZeroDivisionError",
        "StopIteration", "GeneratorExit", "SystemExit", "KeyboardInterrupt"
    ])
    
    private static let successKeywords = Set([
        "pass", "passed", "success", "ok", "OK", "done", "complete",
        "completed", "PASS", "PASSED", "SUCCESS", "DONE", "COMPLETE"
    ])
    
    private static let keywords = Set([
        "import", "from", "def", "class", "return", "if", "else", "elif",
        "for", "while", "try", "except", "finally", "with", "as", "raise",
        "async", "await", "yield", "lambda", "assert", "break", "continue",
        "global", "nonlocal", "in", "is", "not", "and", "or", "let", "const",
        "var", "function", "func", "struct", "enum", "protocol", "extension",
        "public", "private", "static", "final", "override", "mut", "pub",
        "impl", "trait", "mod", "use", "fn", "match", "self", "Self", "super",
        "throws", "throw", "catch", "guard", "defer", "where", "case", "switch",
        "default", "init", "deinit", "get", "set", "willSet", "didSet", "inout"
    ])
    
    private static let decoratorPrefixes = Set(["@"])
    
    static func classify(_ code: String) -> InlineCodeType {
        let trimmed = code.trimmingCharacters(in: .whitespaces)
        
        if looksLikeFilePath(trimmed) {
            return .filePath
        }
        
        if trimmed.hasPrefix("@") {
            return .keyword
        }
        
        if trimmed.hasSuffix("()") || (trimmed.contains("(") && trimmed.contains(")")) {
            return .functionCall
        }
        
        if errorTypes.contains(trimmed) {
            return .errorType
        }
        
        if successKeywords.contains(trimmed) || (trimmed.contains("/") && trimmed.contains("passed")) {
            return .successKeyword
        }
        
        if isTestResult(trimmed) {
            return .testResult
        }
        
        if looksLikeGenericType(trimmed) {
            return .typeOrClass
        }
        
        if pythonTypes.contains(trimmed) || commonTypes.contains(trimmed) {
            return .typeOrClass
        }
        
        let baseType = extractBaseType(trimmed)
        if commonTypes.contains(baseType) || pythonTypes.contains(baseType) {
            return .typeOrClass
        }
        
        if trimmed.first?.isUppercase == true && isValidIdentifier(trimmed) {
            return .typeOrClass
        }
        
        if keywords.contains(trimmed) {
            return .keyword
        }
        
        if Double(trimmed) != nil || Int(trimmed) != nil {
            return .number
        }
        
        if looksLikeVariable(trimmed) {
            return .variable
        }
        
        return .plain
    }
    
    private static func looksLikeFilePath(_ text: String) -> Bool {
        if text.hasPrefix("/") || text.hasPrefix("./") || text.hasPrefix("../") || text.hasPrefix("~") {
            return true
        }
        
        if text.contains("/") && !text.contains(" ") {
            return true
        }
        
        if let lastDot = text.lastIndex(of: ".") {
            let ext = String(text[text.index(after: lastDot)...]).lowercased()
            if fileExtensions.contains(ext) {
                return true
            }
        }
        
        return false
    }
    
    private static func isTestResult(_ text: String) -> Bool {
        let pattern = #"^\d+/\d+\s*(passed|failed|tests?)"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
            let range = NSRange(text.startIndex..., in: text)
            return regex.firstMatch(in: text, range: range) != nil
        }
        return false
    }
    
    private static func looksLikeGenericType(_ text: String) -> Bool {
        guard text.contains("<") && text.contains(">") else { return false }
        guard let angleBracketIndex = text.firstIndex(of: "<") else { return false }
        let basePart = String(text[..<angleBracketIndex])
        return basePart.first?.isUppercase == true && isValidIdentifier(basePart)
    }
    
    private static func extractBaseType(_ text: String) -> String {
        if let angleBracketIndex = text.firstIndex(of: "<") {
            return String(text[..<angleBracketIndex])
        }
        if let bracketIndex = text.firstIndex(of: "[") {
            return String(text[..<bracketIndex])
        }
        return text
    }
    
    private static func isValidIdentifier(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        return text.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }
    
    private static func looksLikeVariable(_ text: String) -> Bool {
        guard !text.isEmpty, let first = text.first else { return false }
        if !first.isLowercase && first != "_" { return false }
        if text.contains(" ") { return false }
        return text.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }
}

extension InlineElement {
    
    func themedNSAttributedString(
        baseFont: NSFont,
        baseColor: NSColor,
        theme: MarkdownThemeProvider
    ) -> NSAttributedString {
        switch self {
        case .code(let code):
            let codeType = InlineCodeClassifier.classify(code)
            let monoFont = NSFont.monospacedSystemFont(ofSize: baseFont.pointSize * 0.92, weight: .medium)
            let color = codeType.color(theme: theme)
            
            let paddedCode = " \(code) "
            
            return NSAttributedString(string: paddedCode, attributes: [
                .font: monoFont,
                .foregroundColor: color,
                .backgroundColor: theme.codeBackground,
                .baselineOffset: 0.5
            ])
            
        case .strong(let content):
            let result = NSMutableAttributedString(
                attributedString: content.themedNSAttributedString(baseFont: baseFont, baseColor: baseColor, theme: theme)
            )
            let boldFont = NSFont.systemFont(ofSize: baseFont.pointSize, weight: .bold)
            result.addAttributes([
                .font: boldFont,
                .foregroundColor: theme.strongColor
            ], range: NSRange(location: 0, length: result.length))
            return result
            
        case .emphasis(let content):
            let result = NSMutableAttributedString(
                attributedString: content.themedNSAttributedString(baseFont: baseFont, baseColor: baseColor, theme: theme)
            )
            let italicFont = NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
            result.addAttributes([
                .font: italicFont,
                .foregroundColor: theme.emphasisColor
            ], range: NSRange(location: 0, length: result.length))
            return result
            
        default:
            return self.nsAttributedString(baseFont: baseFont, baseColor: baseColor)
        }
    }
}

extension MarkdownInlineContent {
    
    func themedNSAttributedString(
        baseFont: NSFont = .systemFont(ofSize: NSFont.systemFontSize),
        baseColor: NSColor = .labelColor,
        theme: MarkdownThemeProvider = MarkdownThemeProvider()
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        
        for element in elements {
            result.append(element.themedNSAttributedString(
                baseFont: baseFont,
                baseColor: baseColor,
                theme: theme
            ))
        }
        
        return result
    }
}
