//
//  PostCreateActionsView.swift
//  aizen
//

import SwiftUI
import CoreData

struct PostCreateActionsView: View {
    @ObservedObject var repository: Repository
    @Binding var showingAddAction: Bool
    @Environment(\.managedObjectContext) var viewContext
    @StateObject var templateManager = PostCreateTemplateStore.shared

    @State var showingTemplates = false
    @State var editingAction: PostCreateAction?
    @State var showGeneratedScript = false
    @State var pendingTemplate: PostCreateTemplate?

    var actions: [PostCreateAction] {
        get { repository.postCreateActions }
        nonmutating set {
            repository.postCreateActions = newValue
            try? viewContext.save()
        }
    }

    var enabledCount: Int {
        actions.filter(\.enabled).count
    }

    var disabledCount: Int {
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

    func moveAction(from index: Int, direction: Int) {
        let destination = index + direction
        guard actions.indices.contains(index), actions.indices.contains(destination) else { return }
        var updatedActions = actions
        let item = updatedActions.remove(at: index)
        updatedActions.insert(item, at: destination)
        actions = updatedActions
    }

    func removeAction(at index: Int) {
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
