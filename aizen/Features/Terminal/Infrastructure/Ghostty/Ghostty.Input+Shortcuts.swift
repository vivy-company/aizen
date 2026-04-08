import AppKit
import GhosttyKit
import SwiftUI

extension Ghostty {
    /// Return the key equivalent for the given trigger.
    ///
    /// Returns nil if the trigger doesn't have an equivalent KeyboardShortcut.
    static func keyboardShortcut(for trigger: ghostty_input_trigger_s) -> KeyboardShortcut? {
        let key: KeyEquivalent
        switch trigger.tag {
        case GHOSTTY_TRIGGER_PHYSICAL:
            if let equiv = Self.keyToEquivalent[trigger.key.physical.rawValue] {
                key = equiv
            } else {
                return nil
            }

        case GHOSTTY_TRIGGER_UNICODE:
            guard let scalar = UnicodeScalar(trigger.key.unicode) else { return nil }
            key = KeyEquivalent(Character(scalar))

        default:
            return nil
        }

        return KeyboardShortcut(
            key,
            modifiers: EventModifiers(nsFlags: Ghostty.eventModifierFlags(mods: trigger.mods))
        )
    }

    static func eventModifierFlags(mods: ghostty_input_mods_e) -> NSEvent.ModifierFlags {
        var flags = NSEvent.ModifierFlags(rawValue: 0)
        if mods.rawValue & GHOSTTY_MODS_SHIFT.rawValue != 0 { flags.insert(.shift) }
        if mods.rawValue & GHOSTTY_MODS_CTRL.rawValue != 0 { flags.insert(.control) }
        if mods.rawValue & GHOSTTY_MODS_ALT.rawValue != 0 { flags.insert(.option) }
        if mods.rawValue & GHOSTTY_MODS_SUPER.rawValue != 0 { flags.insert(.command) }
        return flags
    }

    static func ghosttyMods(_ flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
        var mods: UInt32 = GHOSTTY_MODS_NONE.rawValue

        if flags.contains(.shift) { mods |= GHOSTTY_MODS_SHIFT.rawValue }
        if flags.contains(.control) { mods |= GHOSTTY_MODS_CTRL.rawValue }
        if flags.contains(.option) { mods |= GHOSTTY_MODS_ALT.rawValue }
        if flags.contains(.command) { mods |= GHOSTTY_MODS_SUPER.rawValue }
        if flags.contains(.capsLock) { mods |= GHOSTTY_MODS_CAPS.rawValue }

        let rawFlags = flags.rawValue
        if rawFlags & UInt(NX_DEVICERSHIFTKEYMASK) != 0 { mods |= GHOSTTY_MODS_SHIFT_RIGHT.rawValue }
        if rawFlags & UInt(NX_DEVICERCTLKEYMASK) != 0 { mods |= GHOSTTY_MODS_CTRL_RIGHT.rawValue }
        if rawFlags & UInt(NX_DEVICERALTKEYMASK) != 0 { mods |= GHOSTTY_MODS_ALT_RIGHT.rawValue }
        if rawFlags & UInt(NX_DEVICERCMDKEYMASK) != 0 { mods |= GHOSTTY_MODS_SUPER_RIGHT.rawValue }

        return ghostty_input_mods_e(mods)
    }

    static let keyToEquivalent: [UInt32: KeyEquivalent] = [
        GHOSTTY_KEY_ARROW_UP.rawValue: .upArrow,
        GHOSTTY_KEY_ARROW_DOWN.rawValue: .downArrow,
        GHOSTTY_KEY_ARROW_LEFT.rawValue: .leftArrow,
        GHOSTTY_KEY_ARROW_RIGHT.rawValue: .rightArrow,
        GHOSTTY_KEY_HOME.rawValue: .home,
        GHOSTTY_KEY_END.rawValue: .end,
        GHOSTTY_KEY_DELETE.rawValue: .delete,
        GHOSTTY_KEY_PAGE_UP.rawValue: .pageUp,
        GHOSTTY_KEY_PAGE_DOWN.rawValue: .pageDown,
        GHOSTTY_KEY_ESCAPE.rawValue: .escape,
        GHOSTTY_KEY_ENTER.rawValue: .return,
        GHOSTTY_KEY_TAB.rawValue: .tab,
        GHOSTTY_KEY_BACKSPACE.rawValue: .delete,
        GHOSTTY_KEY_SPACE.rawValue: .space,
    ]
}
