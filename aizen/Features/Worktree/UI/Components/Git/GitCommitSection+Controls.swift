import SwiftUI

extension GitCommitSection {
    var commitButtonMenu: some View {
        HStack(spacing: 0) {
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
    var commitMessageBackground: some View {
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
    var commitControlBackground: some View {
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

    var canCommit: Bool {
        !commitMessage.isEmpty && !gitStatus.stagedFiles.isEmpty && !isOperationPending
    }

    var canOpenMenu: Bool {
        !commitMessage.isEmpty && !isOperationPending
    }

    var commitDividerColor: Color {
        let opacity = (canCommit || canOpenMenu)
            ? (Layout.dividerOpacityEnabled * 2.2)
            : (Layout.dividerOpacityDisabled * 2.2)
        return GitWindowDividerStyle.color(opacity: opacity)
    }

    func commitAllAction() {
        let message = commitMessage

        onStageAll { [self] in
            onCommit(message)
            commitMessage = ""
        }
    }
}
