//
//  PlanContentView.swift
//  aizen
//
//  Markdown content rendering for plans
//

import SwiftUI

struct PlanContentView: View {
    let content: String

    var body: some View {
        MarkdownView(content: content, isStreaming: false)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
