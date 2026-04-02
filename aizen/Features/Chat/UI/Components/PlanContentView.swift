//
//  PlanContentView.swift
//  aizen
//
//  Markdown content rendering for plans
//

import ACP
import SwiftUI

struct PlanContentView: View {
    let content: String

    var body: some View {
        MarkdownView(content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
