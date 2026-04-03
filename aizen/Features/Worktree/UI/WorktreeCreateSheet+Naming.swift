import SwiftUI

extension WorktreeCreateSheet {
    @ViewBuilder
    var namingSection: some View {
        Section("Naming") {
            LabeledContent("Environment Name") {
                TextField("", text: $environmentName, prompt: Text("feature-landing-redesign"))
                    .frame(maxWidth: 280)
            }

            if let warning = environmentNameWarning {
                warningRow(warning)
            }

            if mode == .linked {
                LabeledContent {
                    HStack(spacing: 8) {
                        TextField("", text: branchNameBinding, prompt: Text(branchNamePrompt))
                            .frame(maxWidth: 260)
                            .onSubmit {
                                if !branchName.isEmpty && validationWarning == nil {
                                    createEnvironment()
                                }
                            }
                        Button {
                            generateRandomName()
                        } label: {
                            Image(systemName: "shuffle")
                        }
                        .buttonStyle(.borderless)
                        .help(String(localized: "worktree.create.generateRandom"))
                    }
                } label: {
                    Text(String(localized: "worktree.create.branchName", bundle: .main))
                }

                if !branchNameTemplates.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 6) {
                            ForEach(Array(branchNameTemplates.enumerated()), id: \.offset) { index, template in
                                Button {
                                    if selectedTemplateIndex == index {
                                        selectedTemplateIndex = nil
                                    } else {
                                        selectedTemplateIndex = index
                                        branchName = template
                                    }
                                    validateBranchName()
                                } label: {
                                    Text(template)
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(
                                            selectedTemplateIndex == index
                                                ? Color.accentColor.opacity(0.3)
                                                : Color.secondary.opacity(0.2),
                                            in: Capsule()
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                if let warning = validationWarning {
                    warningRow(warning)
                }
            }
        }
    }
}
