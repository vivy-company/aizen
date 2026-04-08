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
        var eventMonitor: Any?
        var lastMeasuredText: String = ""
        var lastMeasuredWidth: CGFloat = 0
        var lastCursorPosition: Int = -1
        var lastKnownFocus: Bool = false
        var lastCursorText: String = ""
        var didApplyMentionHighlight = false
        static let mentionRegex = try? NSRegularExpression(pattern: "@[^\\s]+", options: [])

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
    }
}
