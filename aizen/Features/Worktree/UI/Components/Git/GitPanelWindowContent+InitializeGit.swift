import SwiftUI

extension GitPanelWindowContent {
    var initializeGitView: some View {
        VStack(spacing: 14) {
            Image(systemName: "externaldrive.badge.plus")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)

            Text("This folder is not a Git project.")
                .font(.headline)

            Text("Initialize Git to enable commits, branches, history, and pull requests.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            if let error = gitInitializationError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            HStack(spacing: 10) {
                Button("Close") {
                    onClose()
                }
                .buttonStyle(.bordered)

                Button {
                    initializeGit()
                } label: {
                    if isInitializingGit {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 80)
                    } else {
                        Text("Initialize Git")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isInitializingGit || worktreePath.isEmpty)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}
