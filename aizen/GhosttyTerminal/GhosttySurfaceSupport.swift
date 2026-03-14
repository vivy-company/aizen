import AppKit
import Carbon
import Foundation
import CoreGraphics

final class CachedValue<T> {
    private var value: T?
    private let fetch: () -> T
    private let duration: Duration
    private var expiryTask: Task<Void, Never>?

    init(duration: Duration, fetch: @escaping () -> T) {
        self.duration = duration
        self.fetch = fetch
    }

    deinit {
        expiryTask?.cancel()
    }

    func get() -> T {
        if let value {
            return value
        }

        let result = fetch()
        let expires = ContinuousClock.now + duration
        value = result

        expiryTask = Task { [weak self] in
            do {
                try await Task.sleep(until: expires)
                self?.value = nil
                self?.expiryTask = nil
            } catch {
            }
        }

        return result
    }
}

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
    static func moveFocus(
        to: Ghostty.SurfaceView,
        from: Ghostty.SurfaceView? = nil,
        delay: TimeInterval? = nil
    ) {
        let maxDelay: TimeInterval = 0.5
        guard (delay ?? 0) < maxDelay else { return }

        let nextDelay: TimeInterval = if let delay {
            delay * 2
        } else {
            0.05
        }

        let work = DispatchWorkItem {
            guard let window = to.window else {
                moveFocus(to: to, from: from, delay: nextDelay)
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
