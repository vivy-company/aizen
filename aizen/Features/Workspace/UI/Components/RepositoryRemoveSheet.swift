import SwiftUI

struct RepositoryRemoveSheet: View {
    let repositoryName: String
    @Binding var alsoDeleteFromFilesystem: Bool
    let onCancel: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.minus")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("workspace.repository.removeTitle")
                .font(.headline)

            Text("workspace.repository.removeMessage")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Toggle(isOn: $alsoDeleteFromFilesystem) {
                Label("workspace.repository.alsoDelete", systemImage: "trash")
                    .foregroundStyle(alsoDeleteFromFilesystem ? .red : .primary)
            }
            .toggleStyle(.checkbox)
            .padding(.top, 6)

            HStack(spacing: 12) {
                Button(String(localized: "worktree.create.cancel")) {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button(String(localized: "workspace.repository.removeButton"), role: .destructive) {
                    onRemove()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 6)
        }
        .padding(24)
        .frame(width: 340)
        .settingsSheetChrome()
    }
}
