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
