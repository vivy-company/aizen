//
//  Clipboard.swift
//  aizen
//
//  Shared pasteboard helper for simple text copies
//

import AppKit

enum Clipboard {
    static func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    static func readString() -> String? {
        NSPasteboard.general.string(forType: .string)
    }

    static func copy(lines: [String], separator: String = "\n") {
        copy(lines.joined(separator: separator))
    }
}
