import SwiftUI

extension WorktreeCreateSheet {
    @ViewBuilder
    var environmentTypeSection: some View {
        Section("Environment Type") {
            Picker("Type", selection: modeBinding) {
                Text(EnvironmentCreationMode.linked.title)
                    .tag(EnvironmentCreationMode.linked)
                    .disabled(!isGitProject)
                Text(EnvironmentCreationMode.independent.title)
                    .tag(EnvironmentCreationMode.independent)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)

            if !isGitProject && mode == .linked {
                warningRow("Linked environments require a git project. Use Independent mode instead.")
            }
        }
    }

    @ViewBuilder
    func warningRow(_ warning: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
            Text(warning)
                .font(.caption)
        }
        .foregroundStyle(.orange)
    }
}
