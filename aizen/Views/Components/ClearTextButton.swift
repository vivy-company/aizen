//
//  ClearTextButton.swift
//  aizen
//
//  Reusable clear-text icon button for search fields
//

import SwiftUI

struct ClearTextButton: View {
    @Binding var text: String
    var size: CGFloat? = nil
    var weight: Font.Weight? = nil
    var color: Color = .secondary
    var opacity: Double = 1.0
    var onClear: (() -> Void)? = nil

    var body: some View {
        Button {
            text = ""
            onClear?()
        } label: {
            icon
                .foregroundStyle(color.opacity(opacity))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Clear"))
    }

    @ViewBuilder
    private var icon: some View {
        let base = Image(systemName: "xmark.circle.fill")
        if let size = size {
            if let weight = weight {
                base.font(.system(size: size, weight: weight))
            } else {
                base.font(.system(size: size))
            }
        } else {
            base
        }
    }
}
