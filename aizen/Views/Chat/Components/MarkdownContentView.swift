//  MarkdownContentView.swift
//  aizen
//
//  Markdown rendering entry points - wrapper views for MarkdownView
//

import SwiftUI

// MARK: - Message Content View

/// Primary entry point for rendering markdown content in chat messages
/// Uses the high-performance NSTextView-based MarkdownView
struct MessageContentView: View {
    let content: String
    var isStreaming: Bool = false

    var body: some View {
        MarkdownView(content: content, isStreaming: isStreaming)
    }
}
