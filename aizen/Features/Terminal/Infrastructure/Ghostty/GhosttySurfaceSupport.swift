import AppKit
import Carbon
import CoreGraphics
import Foundation

enum KeyboardLayout {
    static var id: String? {
        if let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
           let sourceIdPointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) {
            let sourceId = unsafeBitCast(sourceIdPointer, to: CFString.self)
            return sourceId as String
        }

        return nil
    }
}

extension Ghostty {
    /// Copied from Ghostty's SurfaceView.swift and adapted for Aizen's terminal host.
    ///
    /// A `generation` counter is captured at dispatch time and compared at
    /// execution time against `SurfaceView.focusChangeCounter`.  When the two
    /// differ it means another surface claimed first-responder status (e.g. via
    /// a user click) after this call was queued, so executing it would steal
    /// focus.  In that case the work item is silently skipped.
    static func moveFocus(
        to: Ghostty.SurfaceView,
        from: Ghostty.SurfaceView? = nil,
        delay: TimeInterval? = nil,
        generation: Int? = nil
    ) {
        let maxDelay: TimeInterval = 0.5
        guard (delay ?? 0) < maxDelay else { return }

        let gen = generation ?? SurfaceView.focusChangeCounter

        let nextDelay: TimeInterval = if let delay {
            delay * 2
        } else {
            0.05
        }

        let work = DispatchWorkItem {
            // Another surface became first responder since this was dispatched.
            guard SurfaceView.focusChangeCounter == gen else { return }

            guard let window = to.window else {
                moveFocus(to: to, from: from, delay: nextDelay, generation: gen)
                return
            }

            if let from, from !== to {
                _ = from.resignFirstResponder()
            }

            window.makeFirstResponder(to)
        }

        if let delay {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }
}

extension NSScreen {
    var displayID: UInt32? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return deviceDescription[key] as? UInt32
    }
}

extension NSMenuItem {
    func setImageIfDesired(systemSymbolName symbol: String) {
        if #available(macOS 26, *) {
            image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        }
    }
}
