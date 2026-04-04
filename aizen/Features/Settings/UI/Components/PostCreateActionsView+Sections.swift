//
//  PostCreateActionsView+Sections.swift
//  aizen
//

import SwiftUI

extension PostCreateActionsView {
    var overviewSection: some View {
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

    var configuredActionsSection: some View {
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

    var templatesSection: some View {
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

    var advancedSection: some View {
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

    var emptyStateView: some View {
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
}
