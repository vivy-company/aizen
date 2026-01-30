//
//  AllFilesDiffScrollView.swift
//  aizen
//
//  Scrollable list of all file diffs with lazy loading
//

import SwiftUI

struct AllFilesDiffScrollView: View {
    let files: [String]
    let worktreePath: String
    @ObservedObject var diffViewModel: GitDiffViewModel
    @Binding var scrollToFile: String?
    let highlightedFile: String?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 8, pinnedViews: []) {
                    ForEach(files, id: \.self) { file in
                        FileDiffSectionView(
                            file: file,
                            worktreePath: worktreePath,
                            diffViewModel: diffViewModel,
                            isHighlighted: highlightedFile == file
                        )
                        .id(file)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .onChange(of: scrollToFile) { _, file in
                guard let file = file else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(file, anchor: .top)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    scrollToFile = nil
                }
            }
        }
    }
}

// MARK: - Empty State

struct AllFilesDiffEmptyView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundStyle(.green.opacity(0.6))

            Text(String(localized: "git.diff.noChanges"))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)

            Text(String(localized: "git.diff.cleanWorkingTree"))
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
