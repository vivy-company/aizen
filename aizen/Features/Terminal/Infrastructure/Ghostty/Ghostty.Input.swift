import AppKit
import GhosttyKit
import SwiftUI

extension SwiftUI.EventModifiers {
    /// Initialize EventModifiers from NSEvent.ModifierFlags
    init(nsFlags: NSEvent.ModifierFlags) {
        var modifiers = SwiftUI.EventModifiers()
        if nsFlags.contains(.shift) { modifiers.insert(.shift) }
        if nsFlags.contains(.control) { modifiers.insert(.control) }
        if nsFlags.contains(.option) { modifiers.insert(.option) }
        if nsFlags.contains(.command) { modifiers.insert(.command) }
        self = modifiers
    }
}

extension Ghostty {
    // Input types split into separate files: Ghostty.Key.swift, Ghostty.MouseEvent.swift, Ghostty.KeyEvent.swift, Ghostty.Mods.swift
    struct Input {}
}

// MARK: Ghostty.Input.BindingFlags

extension Ghostty.Input {
    struct BindingFlags: OptionSet, Sendable {
        let rawValue: UInt32

        static let consumed = BindingFlags(rawValue: GHOSTTY_BINDING_FLAGS_CONSUMED.rawValue)
        static let all = BindingFlags(rawValue: GHOSTTY_BINDING_FLAGS_ALL.rawValue)
        static let global = BindingFlags(rawValue: GHOSTTY_BINDING_FLAGS_GLOBAL.rawValue)
        static let performable = BindingFlags(rawValue: GHOSTTY_BINDING_FLAGS_PERFORMABLE.rawValue)

        init(rawValue: UInt32) {
            self.rawValue = rawValue
        }

        init(cFlags: ghostty_binding_flags_e) {
            self.rawValue = cFlags.rawValue
        }
    }
}
