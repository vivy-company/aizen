//
//  CustomTextEditor.swift
//  aizen
//
//  Custom NSTextView wrapper for chat input
//

import SwiftUI
import VVCode

struct CustomTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var measuredHeight: CGFloat
    @Binding var isFocused: Bool
    var textInset: CGFloat = 10
    var textTopInset: CGFloat = 6
    let onSubmit: () -> Void

    // Autocomplete callbacks - passes (text, cursorPosition, cursorRect)
    var onCursorChange: ((String, Int, NSRect) -> Void)?
    var onAutocompleteNavigate: ((AutocompleteNavigationAction) -> Bool)?

    // Image paste callback - (imageData, mimeType)
    var onImagePaste: ((Data, String) -> Void)?

    // File paste callback - used to avoid loading file contents on the UI thread
    var onFilePaste: ((URL) -> Void)?

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
        textView.textContainerInset = NSSize(width: textInset, height: textTopInset)
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
        context.coordinator.onFilePaste = onFilePaste
        context.coordinator.onLargeTextPaste = onLargeTextPaste
        context.coordinator.updateMeasuredHeightIfNeeded()

        let hasFocus = textView.window?.firstResponder === textView
        if hasFocus != context.coordinator.lastKnownFocus {
            context.coordinator.lastKnownFocus = hasFocus
            Task { @MainActor in
                context.coordinator.isFocused = hasFocus
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            measuredHeight: $measuredHeight,
            isFocused: $isFocused,
            onSubmit: onSubmit,
            onCursorChange: onCursorChange,
            onAutocompleteNavigate: onAutocompleteNavigate,
            onImagePaste: onImagePaste,
            onFilePaste: onFilePaste,
            onLargeTextPaste: onLargeTextPaste
        )
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        @Binding var measuredHeight: CGFloat
        @Binding var isFocused: Bool
        let onSubmit: () -> Void
        var onCursorChange: ((String, Int, NSRect) -> Void)?
        var onAutocompleteNavigate: ((AutocompleteNavigationAction) -> Bool)?
        var onImagePaste: ((Data, String) -> Void)?
        var onFilePaste: ((URL) -> Void)?
        var onLargeTextPaste: ((String) -> Void)?
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?
        private var eventMonitor: Any?
        var lastMeasuredText: String = ""
        var lastMeasuredWidth: CGFloat = 0
        var lastCursorPosition: Int = -1
        var lastKnownFocus: Bool = false
        var lastCursorText: String = ""
        private var didApplyMentionHighlight = false
        private static let mentionRegex = try? NSRegularExpression(pattern: "@[^\\s]+", options: [])

        init(
            text: Binding<String>,
            measuredHeight: Binding<CGFloat>,
            isFocused: Binding<Bool>,
            onSubmit: @escaping () -> Void,
            onCursorChange: ((String, Int, NSRect) -> Void)?,
            onAutocompleteNavigate: ((AutocompleteNavigationAction) -> Bool)?,
            onImagePaste: ((Data, String) -> Void)?,
            onFilePaste: ((URL) -> Void)?,
            onLargeTextPaste: ((String) -> Void)?
        ) {
            _text = text
            _measuredHeight = measuredHeight
            _isFocused = isFocused
            self.onSubmit = onSubmit
            self.onCursorChange = onCursorChange
            self.onAutocompleteNavigate = onAutocompleteNavigate
            self.onImagePaste = onImagePaste
            self.onFilePaste = onFilePaste
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
                        if CustomTextEditorPasteSupport.handleImagePaste(
                            onImagePaste: self.onImagePaste,
                            onFilePaste: self.onFilePaste
                        ) {
                            return nil // Consume the event
                        }
                        // Try to handle large text paste
                        if CustomTextEditorPasteSupport.handleLargeTextPaste(
                            onLargeTextPaste: self.onLargeTextPaste
                        ) {
                            return nil // Consume the event
                        }
                    }
                }
                return event
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

        func textDidBeginEditing(_ notification: Notification) {
            lastKnownFocus = true
            Task { @MainActor in
                isFocused = true
            }
        }

        func textDidEndEditing(_ notification: Notification) {
            lastKnownFocus = false
            Task { @MainActor in
                isFocused = false
            }
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
            let mentionColor = mentionHighlightColor(for: textView)
            let matches = Self.mentionRegex?.matches(in: text, options: [], range: fullRange) ?? []
            for match in matches {
                attributedString.addAttribute(.foregroundColor, value: mentionColor, range: match.range)
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

        private func mentionHighlightColor(for textView: NSTextView) -> NSColor {
            let isDarkAppearance = textView.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let effectiveThemeName = AppearanceSettings.effectiveThemeName(isDarkAppearance: isDarkAppearance)
            if let theme = GhosttyThemeParser.loadVVTheme(named: effectiveThemeName) {
                return theme.cursorColor
            }
            return NSColor.controlAccentColor
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            notifyCursorChange(textView)
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
    }
}
