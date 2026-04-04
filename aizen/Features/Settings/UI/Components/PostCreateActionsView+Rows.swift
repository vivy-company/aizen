//
//  PostCreateActionsView+Rows.swift
//  aizen
//

import SwiftUI

extension PostCreateActionsView {
    func actionRow(_ action: PostCreateAction, at index: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Toggle("", isOn: Binding(
                    get: { action.enabled },
                    set: { newValue in
                        var updatedActions = actions
                        var updated = action
                        updated.enabled = newValue
                        updatedActions[index] = updated
                        actions = updatedActions
                    }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .padding(.top, 2)

                Image(systemName: action.type.icon)
                    .frame(width: 20)
                    .foregroundStyle(action.enabled ? Color.accentColor : .secondary)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(action.type.displayName)
                            .fontWeight(.medium)

                        if !action.enabled {
                            Text("Disabled")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.secondary.opacity(0.14), in: Capsule())
                        }
                    }

                    Text(actionDescription(action))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    if let metadata = actionMetadata(action) {
                        Text(metadata)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                HStack(spacing: 6) {
                    Button {
                        moveAction(from: index, direction: -1)
                    } label: {
                        Image(systemName: "arrow.up")
                    }
                    .buttonStyle(.borderless)
                    .disabled(index == 0)

                    Button {
                        moveAction(from: index, direction: 1)
                    } label: {
                        Image(systemName: "arrow.down")
                    }
                    .buttonStyle(.borderless)
                    .disabled(index == actions.count - 1)

                    Button {
                        editingAction = action
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.borderless)

                    Button {
                        removeAction(at: index)
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(.vertical, 4)
    }

    func actionDescription(_ action: PostCreateAction) -> String {
        switch action.config {
        case .copyFiles(let config):
            return config.displayPatterns
        case .runCommand(let config):
            return config.command
        case .symlink(let config):
            return "\(config.target) → \(config.source)"
        case .customScript(let config):
            let firstLine = config.script.split(separator: "\n").first ?? ""
            return String(firstLine.prefix(50))
        }
    }

    func actionMetadata(_ action: PostCreateAction) -> String? {
        switch action.config {
        case .copyFiles(let config):
            let count = config.patterns.count
            return "\(count) pattern\(count == 1 ? "" : "s")"
        case .runCommand(let config):
            return "Runs in \(config.workingDirectory.displayName)"
        case .symlink(let config):
            return "Links \(config.source) into \(config.target)"
        case .customScript(let config):
            let lineCount = config.script.split(whereSeparator: \.isNewline).count
            return "\(max(lineCount, 1)) line\(lineCount == 1 ? "" : "s")"
        }
    }

    func summaryMetric(title: String, value: Int, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.title3)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            Color(.controlBackgroundColor).opacity(0.55),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
    }
}
