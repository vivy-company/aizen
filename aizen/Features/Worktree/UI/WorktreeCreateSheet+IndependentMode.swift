import SwiftUI

extension WorktreeCreateSheet {
    @ViewBuilder
    var independentModeSections: some View {
        Section("Source") {
            Text(sourcePath ?? "No source path available")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)

            if !isGitProject {
                Text("Files will be copied into a separate environment.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        if isGitProject {
            Section("Method") {
                Picker("Method", selection: $independentMethod) {
                    Text("Clone")
                        .tag(WorkspaceRepositoryStore.IndependentEnvironmentMethod.clone)
                    Text("Copy")
                        .tag(WorkspaceRepositoryStore.IndependentEnvironmentMethod.copy)
                }
                .labelsHidden()
                .pickerStyle(.segmented)

                Text(independentMethodDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
