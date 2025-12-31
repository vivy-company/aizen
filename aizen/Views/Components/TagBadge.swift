//
//  TagBadge.swift
//  aizen
//
//  Reusable colored badge for short tags
//

import SwiftUI

struct TagBadge: View {
    let text: String
    let color: Color
    var cornerRadius: CGFloat = 4

    var body: some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .cornerRadius(cornerRadius)
    }
}
