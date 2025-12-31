//
//  CodeBlockHeader.swift
//  aizen
//
//  Shared header for code/diagram blocks
//

import SwiftUI

struct CodeBlockHeader: View {
    let iconSystemName: String
    let title: String
    let showsLoading: Bool
    let hasError: Bool
    let errorMessage: String?
    let copyHelpText: String
    let isHovered: Bool
    let headerBackground: Color
    let onCopy: () -> Void

    var iconSize: CGFloat = 11
    var titleFont: Font = .system(size: 11, weight: .medium)
    var loadingSize: CGFloat = 16

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconSystemName)
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(.secondary)

            Text(title)
                .font(titleFont)
                .foregroundStyle(.secondary)

            Spacer()

            if showsLoading {
                ScaledProgressView(size: loadingSize)
            }

            if hasError {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: iconSize))
                    .foregroundStyle(.orange)
                    .help(errorMessage ?? "Render error")
            }

            CopyHoverButton(
                helpText: copyHelpText,
                isHovered: isHovered,
                action: onCopy
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(headerBackground)
    }
}
