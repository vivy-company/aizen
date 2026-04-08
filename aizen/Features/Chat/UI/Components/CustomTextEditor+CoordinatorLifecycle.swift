//
//  CustomTextEditor+CoordinatorLifecycle.swift
//  aizen
//

import SwiftUI
import VVCode

extension CustomTextEditor.Coordinator {
    func setupEventMonitor() {
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
                        return nil
                    }
                    // Try to handle large text paste
                    if CustomTextEditorPasteSupport.handleLargeTextPaste(
                        onLargeTextPaste: self.onLargeTextPaste
                    ) {
                        return nil
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
