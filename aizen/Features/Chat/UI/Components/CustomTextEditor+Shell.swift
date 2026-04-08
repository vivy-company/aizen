//
//  CustomTextEditor+Shell.swift
//  aizen
//

import SwiftUI
import VVCode

extension CustomTextEditor {
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
}
