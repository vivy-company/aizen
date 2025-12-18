import SwiftUI

struct GitCommitSection: View {
    let gitStatus: GitStatus
    let isOperationPending: Bool
    @Binding var commitMessage: String
    let onCommit: (String) -> Void
    let onAmendCommit: (String) -> Void
    let onCommitWithSignoff: (String) -> Void
    let onStageAll: (@escaping () -> Void) -> Void

    var body: some View {
        VStack(spacing: 8) {
            // Commit message
            ZStack(alignment: .topLeading) {
                if commitMessage.isEmpty {
                    Text(String(localized: "git.commit.placeholder"))
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 8)
                        .padding(.top, 8)
                        .allowsHitTesting(false)
                }

                CommitTextEditor(text: $commitMessage)
                    .frame(height: 100)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.3), lineWidth: 1)
            )

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
                    .font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
            }
            .buttonStyle(.plain)
            .background(Color.accentColor)
            .foregroundColor(.white)
            .disabled(commitMessage.isEmpty || gitStatus.stagedFiles.isEmpty || isOperationPending)

            // Divider
            Rectangle()
                .fill(Color.black.opacity(0.2))
                .frame(width: 1, height: 32)

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
                Image(systemName: "chevron.down")
                    .font(.system(size: 8))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 32)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 36)
            .menuIndicator(.hidden)
            .background(Color.accentColor)
            .disabled(commitMessage.isEmpty || isOperationPending)
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(Color.accentColor)
        .cornerRadius(6)
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
