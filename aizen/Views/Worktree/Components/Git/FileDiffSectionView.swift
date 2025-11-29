//
//  FileDiffSectionView.swift
//  aizen
//
//  Collapsible file diff section with lazy loading
//

import SwiftUI

struct FileDiffSectionView: View {
    let file: String
    let worktreePath: String
    @ObservedObject var diffViewModel: GitDiffViewModel
    let isHighlighted: Bool

    @State private var isExpanded: Bool = true
    @State private var loadTask: Task<Void, Never>?

    @AppStorage("editorFontFamily") private var editorFontFamily: String = "Menlo"
    @AppStorage("diffFontSize") private var diffFontSize: Double = 11.0

    private var fileName: String {
        (file as NSString).lastPathComponent
    }

    private var diffLines: [DiffLine]? {
        diffViewModel.loadedDiffs[file]
    }

    private var isLoading: Bool {
        diffViewModel.loadingFiles.contains(file)
    }

    private var error: String? {
        diffViewModel.errors[file]
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
                .id(file)

            if isExpanded {
                contentView
            }
        }
        .background(isHighlighted ? Color.accentColor.opacity(0.08) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onAppear {
            if isExpanded && diffLines == nil && !isLoading {
                loadDiff()
            }
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
        .onChange(of: isExpanded) { expanded in
            if expanded && diffLines == nil && !isLoading {
                loadDiff()
            } else if !expanded {
                loadTask?.cancel()
                loadTask = nil
            }
        }
    }

    private var headerView: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)

                FileIconView(path: file, size: 14)

                Text(fileName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(file)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.head)

                Spacer()

                if let lines = diffLines {
                    diffStats(for: lines)
                }

                if isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 16, height: 16)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func diffStats(for lines: [DiffLine]) -> some View {
        let additions = lines.filter { $0.type == .added }.count
        let deletions = lines.filter { $0.type == .deleted }.count

        HStack(spacing: 6) {
            if additions > 0 {
                Text("+\(additions)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.green)
            }
            if deletions > 0 {
                Text("-\(deletions)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private var contentView: some View {
        if let error = error {
            errorView(error)
        } else if let lines = diffLines {
            if lines.isEmpty {
                emptyView
            } else {
                diffContentView(lines)
            }
        } else if isLoading {
            loadingView
        } else {
            Color.clear.frame(height: 1)
                .onAppear {
                    loadDiff()
                }
        }
    }

    private func errorView(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(12)
    }

    private var emptyView: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)
            Text("No changes")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(12)
    }

    private var loadingView: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.7)
            Text("Loading diff...")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 60)
    }

    private func diffContentView(_ lines: [DiffLine]) -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(lines) { line in
                DiffLineView(
                    line: line,
                    fontSize: diffFontSize,
                    fontFamily: editorFontFamily
                )
            }
        }
    }

    private func loadDiff() {
        loadTask?.cancel()
        loadTask = Task { [weak diffViewModel, file] in
            diffViewModel?.loadDiff(for: file)
        }
    }
}
