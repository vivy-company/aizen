import SwiftUI

extension WorktreeCreateSheet {
    @ViewBuilder
    var postCreateActionsSection: some View {
        let actions = repository.postCreateActions
        let enabledCount = actions.filter { $0.enabled }.count

        Section("Post-Create Actions") {
            Button {
                showingPostCreateActions = true
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    if actions.isEmpty {
                        Image(systemName: "gearshape.2")
                            .font(.body)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("No actions configured")
                                .font(.callout)
                            Text("Tap to add actions that run after environment creation")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(actions.prefix(3)) { action in
                                HStack(spacing: 6) {
                                    Image(systemName: action.enabled ? "checkmark.circle.fill" : "circle")
                                        .font(.caption)
                                        .foregroundStyle(action.enabled ? .green : .secondary)
                                    Image(systemName: action.type.icon)
                                        .font(.caption)
                                        .frame(width: 14)
                                    Text(actionSummary(action))
                                        .font(.caption)
                                        .lineLimit(1)
                                }
                                .foregroundStyle(action.enabled ? .primary : .secondary)
                            }

                            if actions.count > 3 {
                                Text("+\(actions.count - 3) more")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            if enabledCount > 0 {
                Toggle("Run configured actions after creation", isOn: $shouldRunPostCreateActions)

                Text(
                    shouldRunPostCreateActions
                        ? "\(enabledCount) action\(enabledCount == 1 ? "" : "s") will run after creation"
                        : "Configured actions will be skipped for this environment"
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !actions.isEmpty {
                Text("All configured actions are disabled. They won't run until you enable them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            shouldRunPostCreateActions = enabledCount > 0
        }
    }

    func actionSummary(_ action: PostCreateAction) -> String {
        switch action.config {
        case .copyFiles(let config):
            return config.displayPatterns
        case .runCommand(let config):
            return config.command
        case .symlink(let config):
            return "Link \(config.source)"
        case .customScript:
            return "Custom script"
        }
    }
}
