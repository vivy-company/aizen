//
//  JobRowSelectionModifier.swift
//  aizen
//
//  Selection background styling for workflow job rows.
//

import SwiftUI

struct JobRowSelectionModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let isSelected: Bool

    func body(content: Content) -> some View {
        content
            .background(isSelected ? (colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05)) : Color.clear)
    }
}
