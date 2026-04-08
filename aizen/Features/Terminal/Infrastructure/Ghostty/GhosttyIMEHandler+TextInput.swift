import AppKit
import GhosttyKit
import OSLog

@MainActor
extension GhosttyIMEHandler {
    func insertText(_ string: Any, replacementRange: NSRange) {
        guard let text = anyToString(string) else { return }

        clearMarkedText()

        if keyTextAccumulator != nil {
            keyTextAccumulator?.append(text)
            return
        }

        surface?.sendText(text)
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        guard let text = anyToString(string) else { return }

        markedText = text
        markedTextSelectionRange = selectedRange
        syncPreedit(clearIfNeeded: false)

        view?.inputContext?.invalidateCharacterCoordinates()
        view?.needsDisplay = true

        Self.logger.debug("IME marked text: \(text)")
    }

    func unmarkText() {
        if !markedText.isEmpty {
            surface?.sendText(markedText)
            markedText = ""
            markedTextSelectionRange = NSRange(location: NSNotFound, length: 0)
            syncPreedit(clearIfNeeded: true)
            view?.needsDisplay = true
        }
    }

    func selectedRange() -> NSRange {
        markedTextSelectionRange
    }

    func markedRange() -> NSRange {
        if markedText.isEmpty {
            return NSRange(location: NSNotFound, length: 0)
        }
        return NSRange(location: 0, length: markedText.utf16.count)
    }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        guard !markedText.isEmpty else { return nil }

        let attributedString = NSAttributedString(
            string: markedText,
            attributes: markedTextAttributes
        )

        if actualRange != nil {
            actualRange?.pointee = NSRange(location: 0, length: markedText.utf16.count)
        }

        return attributedString
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        [
            .underlineStyle,
            .underlineColor,
            .backgroundColor,
            .foregroundColor,
        ]
    }

    func firstRect(
        forCharacterRange range: NSRange,
        actualRange: NSRangePointer?,
        viewFrame: NSRect,
        window: NSWindow?,
        surface: ghostty_surface_t?
    ) -> NSRect {
        guard let surface = surface else {
            return NSRect(x: viewFrame.origin.x, y: viewFrame.origin.y, width: 0, height: 0)
        }

        var x: Double = 0
        var y: Double = 0
        var width: Double = 0
        var height: Double = 0

        ghostty_surface_ime_point(surface, &x, &y, &width, &height)

        let viewRect = NSRect(
            x: x,
            y: viewFrame.size.height - y,
            width: range.length == 0 ? 0 : max(width, 1),
            height: max(height, 1)
        )

        guard let view = view else { return viewRect }
        let windowRect = view.convert(viewRect, to: nil)

        guard let window = window else { return windowRect }
        return window.convertToScreen(windowRect)
    }

    func characterIndex(for point: NSPoint) -> Int {
        NSNotFound
    }
}
