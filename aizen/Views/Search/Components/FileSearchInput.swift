//
//  FileSearchInput.swift
//  aizen
//
//  Created on 2025-11-19.
//

import SwiftUI

struct FileSearchInput: View {
    @Binding var searchQuery: String
    @FocusState.Binding var isFocused: Bool

    var body: some View {
        SearchField(
            placeholder: "Search files...",
            text: $searchQuery,
            iconSize: 14,
            textFont: .system(size: 14),
            clearButtonSize: 12,
            isFocused: $isFocused,
            trailing: { EmptyView() }
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
