import SwiftUI

extension WorktreeCreateSheet {
    @ViewBuilder
    var linkedModeSections: some View {
        Section(String(localized: "worktree.create.baseBranch", bundle: .main)) {
            BranchSelectorButton(
                selectedBranch: selectedBranch,
                defaultBranch: defaultBaseBranch,
                isPresented: $showingBranchSelector
            )

            Text("worktree.create.baseBranchHelp", bundle: .main)
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Section("Submodules") {
            if loadingSubmodules {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Detecting submodules...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if hasSubmodules {
                Toggle("Initialize submodules after environment creation", isOn: initializeSubmodulesBinding)
                Toggle("Include nested submodules recursively", isOn: $includeNestedSubmodules)
                    .disabled(!initializeSubmodules)

                Text("\(selectedSubmoduleCount) of \(detectedSubmodules.count) submodule\(detectedSubmodules.count == 1 ? "" : "s") selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if initializeSubmodules {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(detectedSubmodules.prefix(8)), id: \.path) { submodule in
                            Toggle(isOn: submoduleSelectionBinding(for: submodule.path)) {
                                Text(submodule.path)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .toggleStyle(.checkbox)
                            .controlSize(.small)
                        }

                        if detectedSubmodules.count > 8 {
                            Text("+\(detectedSubmodules.count - 8) more")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

                    Toggle(
                        "Checkout/create branch '\(branchName.isEmpty ? "new-environment" : branchName)' in selected submodules",
                        isOn: $matchSubmoduleBranchToEnvironment
                    )
                    .disabled(selectedSubmoduleCount == 0 || branchName.isEmpty)
                }
            } else {
                Text("No submodules detected in this repository.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
