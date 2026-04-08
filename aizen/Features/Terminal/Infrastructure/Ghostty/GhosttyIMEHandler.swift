//
//  GhosttyIMEHandler.swift
//  aizen
//
//  Handles Input Method Editor (IME) support for Ghostty terminal
//  Enables proper input for Japanese, Chinese, Korean, etc.
//

import AppKit
import GhosttyKit
import OSLog

/// Manages IME (Input Method Editor) state and text input handling for Ghostty terminal
@MainActor
class GhosttyIMEHandler {
    // MARK: - Properties

    weak var view: NSView?
    weak var surface: Ghostty.Surface?

    /// Track marked text for IME composition
    var markedText: String = ""
    var markedTextSelectionRange = NSRange(location: NSNotFound, length: 0)

    /// Attributes for displaying marked text
    let markedTextAttributes: [NSAttributedString.Key: Any] = [
        .underlineStyle: NSUnderlineStyle.single.rawValue,
        .underlineColor: NSColor.textColor
    ]

    /// Accumulates text from insertText calls during keyDown
    /// Set to non-nil during keyDown to track if IME inserted text
    var keyTextAccumulator: [String]?

    static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "win.aizen.app", category: "GhosttyIME")

    // MARK: - Initialization

    init(view: NSView, surface: Ghostty.Surface?) {
        self.view = view
        self.surface = surface
    }

    // MARK: - Public API

    /// Update surface reference
    func updateSurface(_ surface: Ghostty.Surface?) {
        self.surface = surface
    }

    /// Check if currently composing marked text
    var hasMarkedText: Bool {
        !markedText.isEmpty
    }

    /// Start accumulating text from insertText calls (call before interpretKeyEvents)
    func beginKeyTextAccumulation() {
        keyTextAccumulator = []
    }

    /// End accumulation and return accumulated texts (call after interpretKeyEvents)
    func endKeyTextAccumulation() -> [String]? {
        defer { keyTextAccumulator = nil }
        return keyTextAccumulator
    }

    /// Clear marked text state
    func clearMarkedText() {
        if !markedText.isEmpty {
            markedText = ""
            markedTextSelectionRange = NSRange(location: NSNotFound, length: 0)
            syncPreedit(clearIfNeeded: true)
            view?.needsDisplay = true
        }
    }

    func syncPreedit(clearIfNeeded: Bool) {
        guard let surface = surface?.unsafeCValue else { return }

        if !markedText.isEmpty {
            let len = markedText.utf8CString.count
            markedText.withCString { ptr in
                ghostty_surface_preedit(surface, ptr, UInt(len - 1))
            }
        } else if clearIfNeeded {
            ghostty_surface_preedit(surface, nil, 0)
        }
    }

    func anyToString(_ string: Any) -> String? {
        switch string {
        case let string as NSString:
            return string as String
        case let string as NSAttributedString:
            return string.string
        default:
            return nil
        }
    }
}
