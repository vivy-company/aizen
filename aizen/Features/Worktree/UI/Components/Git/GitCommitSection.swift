import SwiftUI

struct GitCommitSection: View {
    enum Layout {
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
}
