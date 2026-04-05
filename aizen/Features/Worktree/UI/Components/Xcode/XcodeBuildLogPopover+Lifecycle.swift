//
//  XcodeBuildLogPopover+Lifecycle.swift
//  aizen
//
//  Created by OpenAI Codex on 06.04.26.
//

import SwiftUI

extension XcodeBuildLogPopover {
    func copyToClipboard() {
        Clipboard.copy(log)

        showCopiedFeedback = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            showCopiedFeedback = false
        }
    }
}
