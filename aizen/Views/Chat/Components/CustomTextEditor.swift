//
//  CustomTextEditor.swift
//  aizen
//
//  Custom NSTextView wrapper for chat input
//

import SwiftUI

struct CustomTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var measuredHeight: CGFloat
    let onSubmit: () -> Void

    // Autocomplete callbacks - passes (text, cursorPosition, cursorRect)
    var onCursorChange: ((String, Int, NSRect) -> Void)?
    var onAutocompleteNavigate: ((AutocompleteNavigationAction) -> Bool)?

    // Image paste callback - (imageData, mimeType)
    var onImagePaste: ((Data, String) -> Void)?

    // Large text paste callback - text exceeding threshold becomes attachment
    var onLargeTextPaste: ((String) -> Void)?

    // Threshold for converting pasted text to attachment (characters or lines)
    static let largeTextCharacterThreshold = 500
    static let largeTextLineThreshold = 10

    // Cursor position control - when set, moves cursor to this position after text update
    @Binding var pendingCursorPosition: Int?

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView: NSTextView
        if let existing = scrollView.documentView as? NSTextView {
            textView = existing
        } else {
            textView = NSTextView()
            scrollView.documentView = textView
        }

        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay

        textView.delegate = context.coordinator
        textView.font = NSFont.systemFont(ofSize: 14)
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: 0, height: 6)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false

        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView
        context.coordinator.updateMeasuredHeightIfNeeded()

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        context.coordinator.scrollView = nsView

        // Skip text updates during IME composition to avoid breaking CJK input
        if textView.string != text && !textView.hasMarkedText() {
            textView.string = text

            // Apply mention highlighting
            context.coordinator.applyHighlighting(to: textView)

            // If we have a pending cursor position, use it
            if let cursorPos = pendingCursorPosition {
                let safePos = min(cursorPos, text.count)
                textView.setSelectedRange(NSRange(location: safePos, length: 0))
                // Clear the pending position after applying
                DispatchQueue.main.async {
                    self.pendingCursorPosition = nil
                }
            }
        }
        context.coordinator.onCursorChange = onCursorChange
        context.coordinator.onAutocompleteNavigate = onAutocompleteNavigate
        context.coordinator.onImagePaste = onImagePaste
        context.coordinator.onLargeTextPaste = onLargeTextPaste
        context.coordinator.updateMeasuredHeightIfNeeded()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            measuredHeight: $measuredHeight,
            onSubmit: onSubmit,
            onCursorChange: onCursorChange,
            onAutocompleteNavigate: onAutocompleteNavigate,
            onImagePaste: onImagePaste,
            onLargeTextPaste: onLargeTextPaste
        )
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        @Binding var measuredHeight: CGFloat
        let onSubmit: () -> Void
        var onCursorChange: ((String, Int, NSRect) -> Void)?
        var onAutocompleteNavigate: ((AutocompleteNavigationAction) -> Bool)?
        var onImagePaste: ((Data, String) -> Void)?
        var onLargeTextPaste: ((String) -> Void)?
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?
        private var eventMonitor: Any?
        private var lastMeasuredText: String = ""
        private var lastMeasuredWidth: CGFloat = 0
        private var lastCursorPosition: Int = -1
        private var lastCursorText: String = ""
        private var didApplyMentionHighlight = false
        private static let mentionRegex = try? NSRegularExpression(pattern: "@[^\\s]+", options: [])

        init(
            text: Binding<String>,
            measuredHeight: Binding<CGFloat>,
            onSubmit: @escaping () -> Void,
            onCursorChange: ((String, Int, NSRect) -> Void)?,
            onAutocompleteNavigate: ((AutocompleteNavigationAction) -> Bool)?,
            onImagePaste: ((Data, String) -> Void)?,
            onLargeTextPaste: ((String) -> Void)?
        ) {
            _text = text
            _measuredHeight = measuredHeight
            self.onSubmit = onSubmit
            self.onCursorChange = onCursorChange
            self.onAutocompleteNavigate = onAutocompleteNavigate
            self.onImagePaste = onImagePaste
            self.onLargeTextPaste = onLargeTextPaste
            super.init()
            setupEventMonitor()
        }

        deinit {
            if let monitor = eventMonitor {
                NSEvent.removeMonitor(monitor)
            }
        }

        private func setupEventMonitor() {
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self = self else { return event }

                // Check for Cmd+V
                if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "v" {
                    // Check if our text view is first responder
                    if let textView = self.textView,
                       textView.window?.firstResponder === textView {
                        // Try to handle image paste first
                        if self.handleImagePaste() {
                            return nil // Consume the event
                        }
                        // Try to handle large text paste
                        if self.handleLargeTextPaste() {
                            return nil // Consume the event
                        }
                    }
                }
                return event
            }
        }

        private func handleLargeTextPaste() -> Bool {
            guard let onLargeTextPaste = onLargeTextPaste else { return false }
            guard let pastedText = Clipboard.readString() else { return false }

            let lineCount = pastedText.components(separatedBy: .newlines).count
            let charCount = pastedText.count

            // Check if text exceeds thresholds
            if charCount >= CustomTextEditor.largeTextCharacterThreshold ||
               lineCount >= CustomTextEditor.largeTextLineThreshold {
                onLargeTextPaste(pastedText)
                return true
            }

            return false
        }

        private func handleImagePaste() -> Bool {
            guard let onImagePaste = onImagePaste else { return false }

            let pasteboard = NSPasteboard.general

            // Check for PNG data first (most common for screenshots)
            if let data = pasteboard.data(forType: .png) {
                onImagePaste(data, "image/png")
                return true
            }

            // Check for TIFF data (common for copied images)
            if let data = pasteboard.data(forType: .tiff) {
                // Convert TIFF to PNG for better compatibility
                if let image = NSImage(data: data),
                   let tiffData = image.tiffRepresentation,
                   let bitmap = NSBitmapImageRep(data: tiffData),
                   let pngData = bitmap.representation(using: .png, properties: [:]) {
                    onImagePaste(pngData, "image/png")
                    return true
                }
            }

            // Check for file URL that might be an image
            if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
               let url = urls.first {
                let ext = url.pathExtension.lowercased()
                let imageExtensions = ["png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "tiff", "bmp"]
                if imageExtensions.contains(ext) {
                    if let data = try? Data(contentsOf: url) {
                        let mimeType = mimeTypeForExtension(ext)
                        onImagePaste(data, mimeType)
                        return true
                    }
                }
            }

            return false
        }

        private func mimeTypeForExtension(_ ext: String) -> String {
            switch ext.lowercased() {
            case "png": return "image/png"
            case "jpg", "jpeg": return "image/jpeg"
            case "gif": return "image/gif"
            case "webp": return "image/webp"
            case "heic", "heif": return "image/heic"
            case "tiff", "tif": return "image/tiff"
            case "bmp": return "image/bmp"
            default: return "image/png"
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            // Skip updates during IME composition (marked text) to avoid breaking CJK input
            guard !textView.hasMarkedText() else { return }
            text = textView.string
            highlightMentions(in: textView)
            notifyCursorChange(textView)
            updateMeasuredHeightIfNeeded()
        }

        func applyHighlighting(to textView: NSTextView) {
            highlightMentions(in: textView)
        }

        private func highlightMentions(in textView: NSTextView) {
            let text = textView.string
            let fullRange = NSRange(location: 0, length: text.utf16.count)
            let selectedRange = textView.selectedRange()

            if !text.contains("@") {
                guard didApplyMentionHighlight else { return }
                let attributedString = NSAttributedString(
                    string: text,
                    attributes: [
                        .font: NSFont.systemFont(ofSize: 14),
                        .foregroundColor: NSColor.labelColor
                    ]
                )
                textView.textStorage?.setAttributedString(attributedString)
                if selectedRange.location <= text.count {
                    textView.setSelectedRange(selectedRange)
                }
                didApplyMentionHighlight = false
                return
            }

            // Create attributed string with default styling
            let attributedString = NSMutableAttributedString(string: text)
            attributedString.addAttribute(.font, value: NSFont.systemFont(ofSize: 14), range: fullRange)
            attributedString.addAttribute(.foregroundColor, value: NSColor.labelColor, range: fullRange)

            // Find and highlight @mentions (pattern: @followed by non-whitespace until space)
            let matches = Self.mentionRegex?.matches(in: text, options: [], range: fullRange) ?? []
            for match in matches {
                attributedString.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: match.range)
            }

            // Only update if there are actual mentions to highlight
            if !attributedString.isEqual(to: textView.attributedString()) {
                textView.textStorage?.setAttributedString(attributedString)
                // Restore selection
                if selectedRange.location <= text.count {
                    textView.setSelectedRange(selectedRange)
                }
            }
            didApplyMentionHighlight = !matches.isEmpty
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            notifyCursorChange(textView)
        }

        func updateMeasuredHeight() {
            guard let textView = textView,
                  let scrollView = scrollView,
                  let textContainer = textView.textContainer,
                  let layoutManager = textView.layoutManager else {
                return
            }

            textContainer.containerSize = NSSize(width: scrollView.contentSize.width, height: .greatestFiniteMagnitude)
            layoutManager.ensureLayout(for: textContainer)

            let usedRect = layoutManager.usedRect(for: textContainer)
            let inset = textView.textContainerInset.height * 2
            let newHeight = usedRect.height + inset

            if abs(newHeight - measuredHeight) > 0.5 {
                DispatchQueue.main.async { [weak self] in
                    self?.measuredHeight = newHeight
                }
            }
        }

        func updateMeasuredHeightIfNeeded() {
            guard let textView = textView,
                  let scrollView = scrollView else {
                return
            }

            let width = scrollView.contentSize.width
            let text = textView.string

            guard abs(width - lastMeasuredWidth) > 0.5 || text != lastMeasuredText else {
                return
            }

            lastMeasuredWidth = width
            lastMeasuredText = text
            updateMeasuredHeight()
        }

        private func notifyCursorChange(_ textView: NSTextView) {
            let currentText = textView.string
            let cursorPosition = textView.selectedRange().location
            if cursorPosition == lastCursorPosition && currentText == lastCursorText {
                return
            }
            lastCursorPosition = cursorPosition
            lastCursorText = currentText
            if !currentText.contains("@") && !currentText.contains("/") {
                onCursorChange?(currentText, cursorPosition, .zero)
                return
            }
            let cursorRect = cursorScreenRect(for: cursorPosition, in: textView)
            onCursorChange?(currentText, cursorPosition, cursorRect)
        }

        private func cursorScreenRect(for position: Int, in textView: NSTextView) -> NSRect {
            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else {
                return .zero
            }

            let range = NSRange(location: position, length: 0)
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)

            // Add text container inset
            rect.origin.x += textView.textContainerInset.width
            rect.origin.y += textView.textContainerInset.height

            // Convert to window coordinates
            rect = textView.convert(rect, to: nil)

            // Convert to screen coordinates
            if let window = textView.window {
                rect = window.convertToScreen(rect)
            }

            return rect
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            // Handle autocomplete navigation first
            if let navigate = onAutocompleteNavigate {
                if commandSelector == #selector(NSTextView.moveUp(_:)) {
                    if navigate(.up) { return true }
                }
                if commandSelector == #selector(NSTextView.moveDown(_:)) {
                    if navigate(.down) { return true }
                }
                if commandSelector == #selector(NSTextView.cancelOperation(_:)) {
                    if navigate(.dismiss) { return true }
                }
            }

            if commandSelector == #selector(NSTextView.insertNewline(_:)) {
                // Check autocomplete selection first
                if let navigate = onAutocompleteNavigate, navigate(.select) {
                    return true
                }

                if NSEvent.modifierFlags.contains(.shift) {
                    textView.insertNewlineIgnoringFieldEditor(nil)
                    return true
                } else {
                    onSubmit()
                    return true
                }
            }

            // Allow Shift+Tab to be handled by the app (for mode cycling)
            if commandSelector == #selector(NSTextView.insertTab(_:)) && NSEvent.modifierFlags.contains(.shift) {
                return false
            }

            return false
        }

        // Replace text at range and position cursor after
        func replaceText(in range: NSRange, with replacement: String) {
            guard let textView = textView else { return }

            let nsString = textView.string as NSString
            let newText = nsString.replacingCharacters(in: range, with: replacement)
            textView.string = newText
            text = newText

            // Position cursor after replacement
            let newPosition = range.location + replacement.count
            textView.setSelectedRange(NSRange(location: newPosition, length: 0))
            notifyCursorChange(textView)
        }
    }
}
