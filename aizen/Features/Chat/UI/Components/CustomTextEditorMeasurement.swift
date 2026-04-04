//
//  CustomTextEditorMeasurement.swift
//  aizen
//
//  Created by OpenAI Codex on 05.04.26.
//

import AppKit
import Foundation

extension CustomTextEditor.Coordinator {
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
            Task { @MainActor [weak self] in
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
}
