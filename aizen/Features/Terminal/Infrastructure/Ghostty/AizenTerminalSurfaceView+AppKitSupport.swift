import AppKit
import CoreText
import GhosttyKit

// MARK: Services

extension Ghostty.SurfaceView: NSServicesMenuRequestor {
    override func validRequestor(
        forSendType sendType: NSPasteboard.PasteboardType?,
        returnType: NSPasteboard.PasteboardType?
    ) -> Any? {
        let receivable: [NSPasteboard.PasteboardType] = [.string, .init("public.utf8-plain-text")]
        let sendable: [NSPasteboard.PasteboardType] = receivable
        let sendableRequiresSelection = sendable

        if (returnType == nil || receivable.contains(returnType!)) &&
            (sendType == nil || sendable.contains(sendType!)) {
            if let sendType, sendableRequiresSelection.contains(sendType) {
                if surface == nil || !ghostty_surface_has_selection(surface) {
                    return super.validRequestor(forSendType: sendType, returnType: returnType)
                }
            }

            return self
        }

        return super.validRequestor(forSendType: sendType, returnType: returnType)
    }

    func writeSelection(
        to pboard: NSPasteboard,
        types: [NSPasteboard.PasteboardType]
    ) -> Bool {
        guard let surface = self.surface else { return false }

        var text = ghostty_text_s()
        guard ghostty_surface_read_selection(surface, &text) else { return false }
        defer { ghostty_surface_free_text(surface, &text) }

        pboard.declareTypes([.string], owner: nil)
        pboard.setString(String(cString: text.text), forType: .string)
        return true
    }

    func readSelection(from pboard: NSPasteboard) -> Bool {
        guard let str = pboard.getOpinionatedStringContents() else { return false }

        let len = str.utf8CString.count
        if len == 0 { return true }
        str.withCString { ptr in
            ghostty_surface_text(surface, ptr, UInt(len - 1))
        }

        return true
    }
}

// MARK: NSMenuItemValidation

extension Ghostty.SurfaceView: NSMenuItemValidation {
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(pasteSelection):
            let pb = NSPasteboard.ghosttySelection
            guard let str = pb.getOpinionatedStringContents() else { return false }
            return !str.isEmpty

        case #selector(findHide):
            return searchState != nil

        case #selector(toggleReadonly):
            item.state = readonly ? .on : .off
            return true

        default:
            return true
        }
    }
}

// MARK: NSDraggingDestination

extension Ghostty.SurfaceView {
    static let dropTypes: Set<NSPasteboard.PasteboardType> = [
        .string,
        .fileURL,
        .URL
    ]

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard let types = sender.draggingPasteboard.types else { return [] }

        if Set(types).isDisjoint(with: Self.dropTypes) {
            return []
        }

        return .copy
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard

        let content: String?
        if let url = pb.string(forType: .URL) {
            content = Ghostty.Shell.escape(url)
        } else if let urls = pb.readObjects(forClasses: [NSURL.self]) as? [URL], urls.count > 0 {
            content = urls
                .map { Ghostty.Shell.escape($0.path) }
                .joined(separator: " ")
        } else if let str = pb.string(forType: .string) {
            content = str
        } else {
            content = nil
        }

        if let content {
            DispatchQueue.main.async {
                self.insertText(
                    content,
                    replacementRange: NSRange(location: 0, length: 0)
                )
            }
            return true
        }

        return false
    }
}

// MARK: Accessibility

extension Ghostty.SurfaceView {
    override func isAccessibilityElement() -> Bool {
        true
    }

    override func accessibilityRole() -> NSAccessibility.Role? {
        .textArea
    }

    override func accessibilityHelp() -> String? {
        "Terminal content area"
    }

    override func accessibilityValue() -> Any? {
        cachedScreenContents.get()
    }

    override func accessibilitySelectedTextRange() -> NSRange {
        selectedRange()
    }

    override func accessibilitySelectedText() -> String? {
        guard let surface = self.surface else { return nil }

        var text = ghostty_text_s()
        guard ghostty_surface_read_selection(surface, &text) else { return nil }
        defer { ghostty_surface_free_text(surface, &text) }

        let str = String(cString: text.text)
        return str.isEmpty ? nil : str
    }

    override func accessibilityNumberOfCharacters() -> Int {
        let content = cachedScreenContents.get()
        return content.count
    }

    override func accessibilityVisibleCharacterRange() -> NSRange {
        let content = cachedScreenContents.get()
        return NSRange(location: 0, length: content.count)
    }

    override func accessibilityLine(for index: Int) -> Int {
        let content = cachedScreenContents.get()
        let substring = String(content.prefix(index))
        return substring.components(separatedBy: .newlines).count - 1
    }

    override func accessibilityString(for range: NSRange) -> String? {
        let content = cachedScreenContents.get()
        guard let swiftRange = Range(range, in: content) else { return nil }
        return String(content[swiftRange])
    }

    override func accessibilityAttributedString(for range: NSRange) -> NSAttributedString? {
        guard let surface = self.surface else { return nil }
        guard let plainString = accessibilityString(for: range) else { return nil }

        var attributes: [NSAttributedString.Key: Any] = [:]
        if let fontRaw = ghostty_surface_quicklook_font(surface) {
            let font = Unmanaged<CTFont>.fromOpaque(fontRaw)
            attributes[.font] = font.takeUnretainedValue()
            font.release()
        }

        return NSAttributedString(string: plainString, attributes: attributes)
    }
}
