//
//  ANSITextView.swift
//  aizen
//
//  Created by OpenAI Codex on 07.04.26.
//

import SwiftUI

struct ANSITextView: View {
    let text: String
    let fontSize: CGFloat

    init(_ text: String, fontSize: CGFloat = 11) {
        self.text = text
        self.fontSize = fontSize
    }

    var body: some View {
        Text(ANSIParser.parse(text))
            .font(.system(size: fontSize, design: .monospaced))
            .textSelection(.enabled)
    }
}
