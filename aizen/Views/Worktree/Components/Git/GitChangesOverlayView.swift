//
//  GitChangesOverlayView.swift
//  aizen
//
//  Full-screen overlay for viewing all git changes
//

import SwiftUI

struct GitChangesOverlayView: View {
    let worktreePath: String
    let repository: Repository
    let repositoryManager: RepositoryManager
    let gitStatus: GitStatus
    let isOperationPending: Bool
    let onClose: () -> Void

    // Git operation callbacks
    var onStageFile: (String) -> Void
    var onUnstageFile: (String) -> Void
    var onStageAll: (@escaping () -> Void) -> Void
    var onUnstageAll: () -> Void
    var onCommit: (String) -> Void
    var onAmendCommit: (String) -> Void
    var onCommitWithSignoff: (String) -> Void
    var onSwitchBranch: (String) -> Void
    var onCreateBranch: (String) -> Void
    var onFetch: () -> Void
    var onPull: () -> Void
    var onPush: () -> Void

    @StateObject private var diffViewModel: GitDiffViewModel
    @State private var scrollToFile: String?
    @State private var rightPanelWidth: CGFloat = 350

    private let minRightPanelWidth: CGFloat = 300
    private let maxRightPanelWidth: CGFloat = 500

    init(
        worktreePath: String,
        repository: Repository,
        repositoryManager: RepositoryManager,
        gitStatus: GitStatus,
        isOperationPending: Bool,
        onClose: @escaping () -> Void,
        onStageFile: @escaping (String) -> Void,
        onUnstageFile: @escaping (String) -> Void,
        onStageAll: @escaping (@escaping () -> Void) -> Void,
        onUnstageAll: @escaping () -> Void,
        onCommit: @escaping (String) -> Void,
        onAmendCommit: @escaping (String) -> Void,
        onCommitWithSignoff: @escaping (String) -> Void,
        onSwitchBranch: @escaping (String) -> Void,
        onCreateBranch: @escaping (String) -> Void,
        onFetch: @escaping () -> Void,
        onPull: @escaping () -> Void,
        onPush: @escaping () -> Void
    ) {
        self.worktreePath = worktreePath
        self.repository = repository
        self.repositoryManager = repositoryManager
        self.gitStatus = gitStatus
        self.isOperationPending = isOperationPending
        self.onClose = onClose
        self.onStageFile = onStageFile
        self.onUnstageFile = onUnstageFile
        self.onStageAll = onStageAll
        self.onUnstageAll = onUnstageAll
        self.onCommit = onCommit
        self.onAmendCommit = onAmendCommit
        self.onCommitWithSignoff = onCommitWithSignoff
        self.onSwitchBranch = onSwitchBranch
        self.onCreateBranch = onCreateBranch
        self.onFetch = onFetch
        self.onPull = onPull
        self.onPush = onPush
        let untrackedSet = Set(gitStatus.untrackedFiles)
        _diffViewModel = StateObject(wrappedValue: GitDiffViewModel(repoPath: worktreePath, untrackedFiles: untrackedSet))
    }

    private var allChangedFiles: [String] {
        let files = Set(
            gitStatus.stagedFiles +
            gitStatus.modifiedFiles +
            gitStatus.untrackedFiles +
            gitStatus.conflictedFiles
        )
        return Array(files).sorted()
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left: All files diff scroll
            leftPanel
                .frame(maxWidth: .infinity)

            // Divider
            resizableDivider

            // Right: Git sidebar
            rightPanel
                .frame(width: rightPanelWidth)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onExitCommand {
            onClose()
        }
    }

    private var leftPanelHeader: some View {
        HStack(spacing: 8) {
            Button { onClose() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Text(gitStatus.currentBranch ?? "HEAD")
                .font(.system(size: 13, weight: .medium))

            CopyButton(text: gitStatus.currentBranch ?? "", iconSize: 11)

            Spacer()

            HStack(spacing: 8) {
                Text("+\(gitStatus.additions)")
                    .foregroundStyle(.green)
                Text("-\(gitStatus.deletions)")
                    .foregroundStyle(.red)
                Text("\(allChangedFiles.count) files")
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 12, weight: .medium, design: .monospaced))
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var leftPanel: some View {
        VStack(spacing: 0) {
            leftPanelHeader
            Divider()

            if allChangedFiles.isEmpty {
                AllFilesDiffEmptyView()
            } else {
                AllFilesDiffScrollView(
                    files: allChangedFiles,
                    worktreePath: worktreePath,
                    diffViewModel: diffViewModel,
                    scrollToFile: $scrollToFile,
                    highlightedFile: diffViewModel.visibleFile
                )
            }
        }
    }

    private var resizableDivider: some View {
        Rectangle()
            .fill(Color(NSColor.separatorColor))
            .frame(width: 1)
            .overlay(
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 8)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let newWidth = rightPanelWidth - value.translation.width
                                rightPanelWidth = min(max(newWidth, minRightPanelWidth), maxRightPanelWidth)
                            }
                    )
                    .onHover { hovering in
                        if hovering {
                            NSCursor.resizeLeftRight.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
            )
    }

    private var rightPanel: some View {
        GitSidebarView(
            worktreePath: worktreePath,
            repository: repository,
            repositoryManager: repositoryManager,
            onClose: onClose,
            gitStatus: gitStatus,
            isOperationPending: isOperationPending,
            selectedDiffFile: diffViewModel.visibleFile,
            onStageFile: { file in
                onStageFile(file)
                Task {
                    await diffViewModel.invalidateFile(file)
                }
            },
            onUnstageFile: { file in
                onUnstageFile(file)
                Task {
                    await diffViewModel.invalidateFile(file)
                }
            },
            onStageAll: { completion in
                onStageAll {
                    Task {
                        await diffViewModel.invalidateCache()
                    }
                    completion()
                }
            },
            onUnstageAll: {
                onUnstageAll()
                Task {
                    await diffViewModel.invalidateCache()
                }
            },
            onCommit: { message in
                onCommit(message)
                Task {
                    await diffViewModel.invalidateCache()
                }
            },
            onAmendCommit: { message in
                onAmendCommit(message)
                Task {
                    await diffViewModel.invalidateCache()
                }
            },
            onCommitWithSignoff: { message in
                onCommitWithSignoff(message)
                Task {
                    await diffViewModel.invalidateCache()
                }
            },
            onSwitchBranch: { branch in
                onSwitchBranch(branch)
                Task {
                    await diffViewModel.invalidateCache()
                }
            },
            onCreateBranch: onCreateBranch,
            onFetch: onFetch,
            onPull: {
                onPull()
                Task {
                    await diffViewModel.invalidateCache()
                }
            },
            onPush: onPush,
            onFileClick: { file in
                scrollToFile = file
            }
        )
    }
}
