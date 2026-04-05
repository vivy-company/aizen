import SwiftUI

extension GitCommitSection {
    var body: some View {
        VStack(spacing: Layout.sectionSpacing) {
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

            commitButtonMenu
        }
    }
}
