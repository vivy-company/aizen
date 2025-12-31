//
//  ValidationStatusIcon.swift
//  aizen
//
//  Simple valid/invalid status icon with optional help text
//

import SwiftUI

struct ValidationStatusIcon: View {
    let isValid: Bool
    var size: CGFloat? = nil
    var validHelp: String? = nil
    var invalidHelp: String? = nil
    var validColor: Color = .green
    var invalidColor: Color = .red

    var body: some View {
        let image = Image(systemName: isValid ? "checkmark.circle.fill" : "xmark.circle.fill")
        let colored = image.foregroundColor(isValid ? validColor : invalidColor)

        if let size = size {
            if let help = helpText {
                colored
                    .font(.system(size: size))
                    .help(help)
            } else {
                colored
                    .font(.system(size: size))
            }
        } else {
            if let help = helpText {
                colored
                    .help(help)
            } else {
                colored
            }
        }
    }

    private var helpText: String? {
        isValid ? validHelp : invalidHelp
    }
}
