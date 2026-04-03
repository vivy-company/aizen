import VVCode
import SwiftUI

extension GitPanelWindowContent {
    var diffRenderStylePicker: some View {
        Picker("Diff Layout", selection: $diffRenderStyle) {
            Text("Inline").tag(VVDiffRenderStyle.inline)
            Text("Split").tag(VVDiffRenderStyle.sideBySide)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
        .frame(width: 128)
        .help("Switch between inline and side-by-side diff layouts")
    }

    func changesDiffHeader() -> some View {
        HStack(spacing: 8) {
            Image(systemName: GitPanelTab.git.icon)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Text(GitPanelTab.git.displayName)
                .font(.system(size: 13, weight: .medium))

            Spacer()

            diffRenderStylePicker
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
    }

    func diffPanelHeader(for commit: GitCommit) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Text(commit.shortHash)
                .font(.system(size: 13, weight: .medium, design: .monospaced))

            Text(commit.message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            diffRenderStylePicker

            Button(String(localized: "git.panel.backToChanges")) {
                selectedHistoryCommit = nil
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
    }

    var diffPanel: some View {
        VStack(spacing: 0) {
            if let commit = selectedHistoryCommit {
                diffPanelHeader(for: commit)
            } else {
                changesDiffHeader()
            }

            if selectedHistoryCommit == nil && allChangedFiles.isEmpty {
                AllFilesDiffEmptyView()
            } else if effectiveDiffOutput.isEmpty {
                VStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(String(localized: "git.diff.loading"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                DiffView(
                    diffOutput: effectiveDiffOutput,
                    fontSize: diffFontSize,
                    fontFamily: editorFontFamily,
                    repoPath: worktreePath,
                    renderStyle: diffRenderStyle,
                    scrollToFile: scrollToFile,
                    onFileVisible: { file in
                        visibleFile = file
                    },
                    onOpenFile: { file in
                        let fullPath = (worktreePath as NSString).appendingPathComponent(file)
                        NotificationCenter.default.post(
                            name: .openFileInEditor,
                            object: nil,
                            userInfo: ["path": fullPath]
                        )
                        onClose()
                    },
                    commentedLines: selectedHistoryCommit == nil ? reviewManager.commentedLineKeys : Set(),
                    onAddComment: selectedHistoryCommit == nil ? { line, filePath in
                        commentPopoverFilePath = filePath
                        commentPopoverLine = line
                    } : { _, _ in }
                )
            }
        }
        .task(id: effectiveDiffOutput) {
            validateCommentsAgainstDiff()
        }
    }
}
