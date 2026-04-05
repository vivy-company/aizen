//
//  WorktreeListItemView+Content.swift
//  aizen
//
//  Row content and context menu composition for worktree list items.
//

import SwiftUI

extension WorktreeListItemView {
    var rowContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                if worktree.isPrimary {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 14, height: 14)
                        .foregroundStyle(
                            isSelected
                                ? selectedForegroundColor
                                : Color(nsColor: .systemOrange).opacity(0.88)
                        )
                        .help(String(localized: "worktree.detail.main"))
                }

                Text(worktree.branch ?? String(localized: "worktree.list.unknown"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(primaryTextColor)
                    .lineLimit(1)

                Spacer(minLength: 8)

                sessionIcons
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let note = worktree.note, !note.isEmpty {
                Text(note)
                    .font(.subheadline)
                    .foregroundStyle(secondaryTextColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }
}
