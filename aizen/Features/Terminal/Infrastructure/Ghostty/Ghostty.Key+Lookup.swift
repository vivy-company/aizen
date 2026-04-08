import Foundation

extension Ghostty.Input.Key {
    /// Get a key from a keycode.
    init?(keyCode: UInt16) {
        if let key = Self.allCases.first(where: { $0.keyCode == keyCode }) {
            self = key
            return
        }

        return nil
    }
}
