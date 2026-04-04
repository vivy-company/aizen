//
//  CustomTextEditorCursorSupport.swift
//  aizen
//
//  Created by OpenAI Codex on 05.04.26.
//

import AppKit
import Foundation

extension CustomTextEditor.Coordinator {
    func notifyCursorChange(_ textView: NSTextView) {
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

    func replaceText(in range: NSRange, with replacement: String) {
        guard let textView = textView else { return }

        let nsString = textView.string as NSString
        let newText = nsString.replacingCharacters(in: range, with: replacement)
        textView.string = newText
        text = newText

        let newPosition = range.location + replacement.count
        textView.setSelectedRange(NSRange(location: newPosition, length: 0))
        notifyCursorChange(textView)
    }

    private func cursorScreenRect(for position: Int, in textView: NSTextView) -> NSRect {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return .zero
        }

        let range = NSRange(location: position, length: 0)
        let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)

        rect.origin.x += textView.textContainerInset.width
        rect.origin.y += textView.textContainerInset.height
        rect = textView.convert(rect, to: nil)

        if let window = textView.window {
            rect = window.convertToScreen(rect)
        }

        return rect
    }
}
