//
//  PostCreateActionsView.swift
//  aizen
//

import SwiftUI
import CoreData

struct PostCreateActionsView: View {
    @ObservedObject var repository: Repository
    @Binding var showingAddAction: Bool
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var templateManager = PostCreateTemplateStore.shared

    @State private var showingTemplates = false
    @State private var editingAction: PostCreateAction?
    @State private var showGeneratedScript = false
    @State private var pendingTemplate: PostCreateTemplate?

    private var actions: [PostCreateAction] {
        get { repository.postCreateActions }
        nonmutating set {
            repository.postCreateActions = newValue
            try? viewContext.save()
        }
    }

    private var enabledCount: Int {
        actions.filter(\.enabled).count
    }

    private var disabledCount: Int {
        actions.count - enabledCount
    }

    var body: some View {
        Form {
            overviewSection
            configuredActionsSection
            templatesSection

            if !actions.isEmpty {
                advancedSection
            }
        }
        .formStyle(.grouped)
        .settingsSurface()
        .alert("Replace current actions?", isPresented: Binding(
            get: { pendingTemplate != nil },
            set: { newValue in
                if !newValue {
                    pendingTemplate = nil
                }
            }
        )) {
            Button("Cancel", role: .cancel) {
                pendingTemplate = nil
            }
            Button("Replace", role: .destructive) {
                if let pendingTemplate {
                    actions = pendingTemplate.actions
                }
                pendingTemplate = nil
            }
        } message: {
            if let pendingTemplate {
                Text("Applying \"\(pendingTemplate.name)\" will replace the current action list.")
            }
        }
        .sheet(isPresented: $showingAddAction) {
            PostCreateActionEditorSheet(
                action: nil,
                onSave: { action in
                    actions = actions + [action]
                },
                onCancel: {},
                repositoryPath: repository.path
            )
        }
        .sheet(item: $editingAction) { action in
            PostCreateActionEditorSheet(
                action: action,
                onSave: { updated in
                    var updatedActions = actions
                    if let index = updatedActions.firstIndex(where: { $0.id == updated.id }) {
                        updatedActions[index] = updated
                        actions = updatedActions
                    }
                },
                onCancel: {},
                repositoryPath: repository.path
            )
        }
        .sheet(isPresented: $showingTemplates) {
            PostCreateTemplatesSheet(
                onSelect: { template in
                    applyTemplate(template)
                }
            )
        }
    }

    private var overviewSection: some View {
        Section("Overview") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Configure follow-up steps that run automatically after a new environment is created.")
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    summaryMetric(title: "Total", value: actions.count, systemImage: "list.bullet.rectangle")
                    summaryMetric(title: "Enabled", value: enabledCount, systemImage: "checkmark.circle")
                    summaryMetric(title: "Disabled", value: disabledCount, systemImage: "pause.circle")
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var configuredActionsSection: some View {
        Section("Configured Actions") {
            if actions.isEmpty {
                emptyStateView
            } else {
                ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                    actionRow(action, at: index)
                }

                Button {
                    showingAddAction = true
                } label: {
                    Label("Add Action", systemImage: "plus")
                }

                Button(role: .destructive) {
                    actions = []
                } label: {
                    Label("Clear All Actions", systemImage: "trash")
                }
            }
        }
    }

    private var templatesSection: some View {
        Section("Templates") {
            Button {
                showingTemplates = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "doc.on.doc")
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Apply Template")
                            .foregroundStyle(.primary)
                        Text(actions.isEmpty ? "Start from a built-in or custom action set." : "Replaces the current action list.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var advancedSection: some View {
        Section("Advanced") {
            DisclosureGroup(isExpanded: $showGeneratedScript) {
                ScrollView {
                    Text(PostCreateScriptGenerator.generateScript(from: actions))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(height: 180)
                .background(Color(.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding(.top, 6)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Generated Script", systemImage: "scroll")
                    Text("Preview the shell script Aizen will run for enabled actions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "gearshape.2")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text("No actions configured")
                        .fontWeight(.medium)
                    Text("Add individual steps or start from a template.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                Button {
                    showingAddAction = true
                } label: {
                    Label("Add Action", systemImage: "plus")
                }
                .buttonStyle(.bordered)

                Button {
                    showingTemplates = true
                } label: {
                    Label("Use Template", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.vertical, 6)
    }

    private func actionRow(_ action: PostCreateAction, at index: Int) -> some View {
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

    private func actionDescription(_ action: PostCreateAction) -> String {
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

    private func actionMetadata(_ action: PostCreateAction) -> String? {
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

    private func summaryMetric(title: String, value: Int, systemImage: String) -> some View {
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
        .background(Color(.controlBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func moveAction(from index: Int, direction: Int) {
        let destination = index + direction
        guard actions.indices.contains(index), actions.indices.contains(destination) else { return }
        var updatedActions = actions
        let item = updatedActions.remove(at: index)
        updatedActions.insert(item, at: destination)
        actions = updatedActions
    }

    private func removeAction(at index: Int) {
        guard actions.indices.contains(index) else { return }
        var updatedActions = actions
        updatedActions.remove(at: index)
        actions = updatedActions
    }

    private func applyTemplate(_ template: PostCreateTemplate) {
        if actions.isEmpty {
            actions = template.actions
        } else {
            pendingTemplate = template
        }
    }
}
