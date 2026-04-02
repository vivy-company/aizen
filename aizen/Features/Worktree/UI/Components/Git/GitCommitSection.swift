import SwiftUI

struct GitCommitSection: View {
    private enum Layout {
        static let sectionSpacing: CGFloat = 10
        static let cornerRadius: CGFloat = 12
        static let messageHeight: CGFloat = 100
        static let buttonHeight: CGFloat = 40
        static let menuWidth: CGFloat = 48
        static let menuIconSize: CGFloat = 14
        static let placeholderInset: CGFloat = 10
        static let dividerWidth: CGFloat = 1
        static let dividerVerticalInset: CGFloat = 7
        static let dividerOpacityEnabled: CGFloat = 0.26
        static let dividerOpacityDisabled: CGFloat = 0.14
    }

    let gitStatus: GitStatus
    let isOperationPending: Bool
    @Binding var commitMessage: String
    let onCommit: (String) -> Void
    let onAmendCommit: (String) -> Void
    let onCommitWithSignoff: (String) -> Void
    let onStageAll: (@escaping () -> Void) -> Void

    var body: some View {
        VStack(spacing: Layout.sectionSpacing) {
            // Commit message
            ZStack(alignment: .topLeading) {
                if commitMessage.isEmpty {
                    Text(String(localized: "git.commit.placeholder"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, Layout.placeholderInset)
                        .padding(.top, Layout.placeholderInset)
                        .allowsHitTesting(false)
                }

                CommitTextEditor(text: $commitMessage)
                    .frame(height: Layout.messageHeight)
            }
            .background { commitMessageBackground }
            .clipShape(RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
                    .stroke(GitWindowDividerStyle.color(opacity: 0.22), lineWidth: 0.5)
            }

            // Commit button menu
            commitButtonMenu
        }
    }

    private var commitButtonMenu: some View {
        HStack(spacing: 0) {
            // Main commit button
            Button {
                onCommit(commitMessage)
                commitMessage = ""
            } label: {
                Text(String(localized: "git.commit.button"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: Layout.buttonHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canCommit)

            Rectangle()
                .fill(commitDividerColor)
                .frame(width: Layout.dividerWidth)
                .padding(.vertical, Layout.dividerVerticalInset)
                .allowsHitTesting(false)

            // Dropdown menu
            Menu {
                Button(String(localized: "git.commit.commitAll")) {
                    commitAllAction()
                }
                Divider()
                Button(String(localized: "git.commit.amend")) {
                    onAmendCommit(commitMessage)
                    commitMessage = ""
                }
                .disabled(gitStatus.stagedFiles.isEmpty)
                Button(String(localized: "git.commit.signoff")) {
                    onCommitWithSignoff(commitMessage)
                    commitMessage = ""
                }
                .disabled(gitStatus.stagedFiles.isEmpty)
            } label: {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: Layout.menuIconSize, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: Layout.menuWidth, height: Layout.buttonHeight)
            .disabled(!canOpenMenu)
        }
        .frame(height: Layout.buttonHeight)
        .background { commitControlBackground }
        .clipShape(RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
                .stroke(GitWindowDividerStyle.color(opacity: 0.14), lineWidth: 0.5)
        }
    }

    @ViewBuilder
    private var commitMessageBackground: some View {
        let shape = RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            GlassEffectContainer {
                shape
                    .fill(.white.opacity(0.001))
                    .glassEffect(.regular, in: shape)
                shape
                    .fill(.white.opacity(0.03))
            }
        } else {
            shape.fill(.ultraThinMaterial)
        }
    }

    @ViewBuilder
    private var commitControlBackground: some View {
        let shape = RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            GlassEffectContainer {
                shape
                    .fill(.white.opacity(0.001))
                    .glassEffect(.regular.tint(.accentColor.opacity(0.9)).interactive(), in: shape)
                shape
                    .fill(Color.accentColor.opacity(0.16))
            }
        } else {
            shape.fill(Color.accentColor)
        }
    }

    private var canCommit: Bool {
        !commitMessage.isEmpty && !gitStatus.stagedFiles.isEmpty && !isOperationPending
    }

    private var canOpenMenu: Bool {
        !commitMessage.isEmpty && !isOperationPending
    }

    private var commitDividerColor: Color {
        let opacity = (canCommit || canOpenMenu) ? (Layout.dividerOpacityEnabled * 2.2) : (Layout.dividerOpacityDisabled * 2.2)
        return GitWindowDividerStyle.color(opacity: opacity)
    }

    private func commitAllAction() {
        let message = commitMessage

        // Stage all files, then commit when staging completes
        onStageAll { [self] in
            onCommit(message)
            commitMessage = ""
        }
    }
}
