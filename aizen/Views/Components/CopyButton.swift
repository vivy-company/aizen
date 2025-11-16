//
//  CopyButton.swift
//  aizen
//
//  Reusable copy button with visual feedback
//

import SwiftUI

struct CopyButton: View {
    let text: String
    let iconSize: CGFloat

    @State private var showConfirmation = false

    init(text: String, iconSize: CGFloat = 10) {
        self.text = text
        self.iconSize = iconSize
    }

    var body: some View {
        Button(action: copyToClipboard) {
            Image(systemName: showConfirmation ? "checkmark" : "doc.on.doc")
                .font(.system(size: iconSize))
                .foregroundColor(showConfirmation ? .green : .secondary)
        }
        .buttonStyle(.plain)
        .help("Copy to clipboard")
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        withAnimation {
            showConfirmation = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showConfirmation = false
            }
        }
    }
}
