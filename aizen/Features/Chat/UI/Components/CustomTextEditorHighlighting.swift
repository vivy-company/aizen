//
//  CustomTextEditorHighlighting.swift
//  aizen
//
//  Created by OpenAI Codex on 05.04.26.
//

import AppKit
import Foundation
import VVCode

extension CustomTextEditor.Coordinator {
    func applyHighlighting(to textView: NSTextView) {
        highlightMentions(in: textView)
    }

    func highlightMentions(in textView: NSTextView) {
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

        let attributedString = NSMutableAttributedString(string: text)
        attributedString.addAttribute(.font, value: NSFont.systemFont(ofSize: 14), range: fullRange)
        attributedString.addAttribute(.foregroundColor, value: NSColor.labelColor, range: fullRange)

        let mentionColor = mentionHighlightColor(for: textView)
        let matches = Self.mentionRegex?.matches(in: text, options: [], range: fullRange) ?? []
        for match in matches {
            attributedString.addAttribute(.foregroundColor, value: mentionColor, range: match.range)
        }

        if !attributedString.isEqual(to: textView.attributedString()) {
            textView.textStorage?.setAttributedString(attributedString)
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
}
